Set-StrictMode -Version Latest

BeforeAll {
    . (Join-Path (Split-Path -Path $PSScriptRoot -Parent) '_testHelpers.ps1')
    Import-IdleTestModule
    $script:FixturesPath = Join-Path $PSScriptRoot '..' 'fixtures/workflows'

    # The engine invokes step handlers by function name (string) inside module scope.
    # Therefore, test handler functions must be visible to the module (global scope).
    function global:Invoke-IdleTestNoopStep {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [ValidateNotNull()]
            [object] $Context,

            [Parameter(Mandatory)]
            [ValidateNotNull()]
            [object] $Step
        )

        return [pscustomobject]@{
            PSTypeName = 'IdLE.StepResult'
            Name       = [string]$Step.Name
            Type       = [string]$Step.Type
            Status     = 'Completed'
            Error      = $null
        }
    }

    function global:Invoke-IdleTestEmitStep {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [ValidateNotNull()]
            [object] $Context,

            [Parameter(Mandatory)]
            [ValidateNotNull()]
            [object] $Step
        )

        $Context.EventSink.WriteEvent('Custom', 'Hello from test step', $Step.Name, @{ StepType = $Step.Type })

        return [pscustomobject]@{
            PSTypeName = 'IdLE.StepResult'
            Name       = [string]$Step.Name
            Type       = [string]$Step.Type
            Status     = 'Completed'
            Error      = $null
        }
    }

    function global:Invoke-IdleTestFailStep {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [ValidateNotNull()]
            [object] $Context,

            [Parameter(Mandatory)]
            [ValidateNotNull()]
            [object] $Step
        )

        return [pscustomobject]@{
            PSTypeName = 'IdLE.StepResult'
            Name       = [string]$Step.Name
            Type       = [string]$Step.Type
            Status     = 'Failed'
            Error      = 'Boom'
        }
    }

    function global:Invoke-IdleTestAcquireAuthSessionStep {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [ValidateNotNull()]
            [object] $Context,

            [Parameter(Mandatory)]
            [ValidateNotNull()]
            [object] $Step
        )

        $with = $Step.With
        $name = $null
        $options = $null

        if ($with -is [System.Collections.IDictionary]) {
            if ($with.Contains('Name')) {
                $name = [string]$with['Name']
            }

            if ($with.Contains('Options')) {
                $options = $with['Options']
            }
        }
        else {
            if ($null -ne $with -and $with.PSObject.Properties.Name -contains 'Name') {
                $name = [string]$with.Name
            }

            if ($null -ne $with -and $with.PSObject.Properties.Name -contains 'Options') {
                $options = $with.Options
            }
        }

        $session = $Context.AcquireAuthSession($name, $options)

        if ($null -eq $session) {
            throw [System.InvalidOperationException]::new('AcquireAuthSession returned null.')
        }

        return [pscustomobject]@{
            PSTypeName = 'IdLE.StepResult'
            Name       = [string]$Step.Name
            Type       = [string]$Step.Type
            Status     = 'Completed'
            Error      = $null
        }
    }

    # Legacy step handler without Context parameter for backwards compatibility testing
    function global:Invoke-IdleTestLegacyStep {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [ValidateNotNull()]
            [object] $Step
        )

        return [pscustomobject]@{
            PSTypeName = 'IdLE.StepResult'
            Name       = [string]$Step.Name
            Type       = [string]$Step.Type
            Status     = 'Completed'
            Error      = $null
        }
    }
}

AfterAll {
    # Cleanup global test functions to avoid polluting the session.
    Remove-Item -Path 'Function:\Invoke-IdleTestNoopStep' -ErrorAction SilentlyContinue
    Remove-Item -Path 'Function:\Invoke-IdleTestEmitStep' -ErrorAction SilentlyContinue
    Remove-Item -Path 'Function:\Invoke-IdleTestFailStep' -ErrorAction SilentlyContinue
    Remove-Item -Path 'Function:\Invoke-IdleTestAcquireAuthSessionStep' -ErrorAction SilentlyContinue
    Remove-Item -Path 'Function:\Invoke-IdleTestLegacyStep' -ErrorAction SilentlyContinue
}

Describe 'Invoke-IdlePlan' {
    Context 'Execution results' {
        It 'returns an execution result with events in deterministic order' {
            $wfPath = Join-Path $script:FixturesPath 'invoke-two-emitevent-steps.psd1'

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner'

            $providers = @{
                StepRegistry = @{
                    'Test.IdLE.Step.Emit' = 'Invoke-IdleTestNoopStep'
                }
                StepMetadata = New-IdleTestStepMetadata -StepTypes @('Test.IdLE.Step.Emit')
            }

            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

            $result = Invoke-IdlePlan -Plan $plan -Providers $providers

            $result.PSTypeNames | Should -Contain 'IdLE.ExecutionResult'
            $result.Status | Should -Be 'Completed'
            @($result.Steps).Count | Should -Be 2

            @($result.Events).Count | Should -BeGreaterThan 0
            $result.Events[0].Type | Should -Be 'RunStarted'
            $result.Events[-1].Type | Should -Be 'RunCompleted'

            $result.Steps[0].Status | Should -Be 'Completed'
            $result.Steps[1].Status | Should -Be 'Completed'
        }

        It 'supports -WhatIf and does not execute' {
            $plan = [pscustomobject]@{
                CorrelationId = 'test'
                Steps         = @(
                    @{ Name = 'A'; Type = 'X' }
                )
            }

            $result = Invoke-IdlePlan -Plan $plan -WhatIf
            $result.Status | Should -Be 'WhatIf'
            @($result.Events).Count | Should -Be 0
        }
    }

    Context 'Event sinks' {
        It 'can stream events to an object sink with WriteEvent(event)' {
            $wfPath = New-IdleTestWorkflowFile -FileName 'joiner.psd1' -Content @'
@{
  Name           = 'Joiner - Standard'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{ Name = 'ResolveIdentity'; Type = 'Test.IdLE.Step.ResolveIdentity' }
  )
}
'@

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner'

            $providers = @{
                StepRegistry = @{
                    'Test.IdLE.Step.ResolveIdentity' = 'Invoke-IdleTestNoopStep'
                }
                StepMetadata = New-IdleTestStepMetadata -StepTypes @('Test.IdLE.Step.ResolveIdentity')
            }

            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

            $sinkEvents = [System.Collections.Generic.List[object]]::new()
            $sinkObject = [pscustomobject]@{}
            $writeMethod = {
                param($e)
                [void]$sinkEvents.Add($e)
            }.GetNewClosure()
            $null = Add-Member -InputObject $sinkObject -MemberType ScriptMethod -Name 'WriteEvent' -Value $writeMethod -Force

            $result = Invoke-IdlePlan -Plan $plan -Providers $providers -EventSink $sinkObject

            $sinkEvents.Count | Should -BeGreaterThan 0
            $sinkEvents[0].PSTypeNames | Should -Contain 'IdLE.Event'
            $result.Events[0].Type | Should -Be 'RunStarted'
        }
    }

    Context 'Step execution' {
        It 'executes a registered step and returns Completed status' {
            $wfPath = New-IdleTestWorkflowFile -FileName 'emit.psd1' -Content @'
@{
  Name           = 'Demo'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{ Name = 'Emit'; Type = 'Test.IdLE.Step.Emit'; With = @{ Message = 'Hello' } }
  )
}
'@

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner'

            $providers = @{
                StepRegistry = @{
                    'Test.IdLE.Step.Emit' = 'Invoke-IdleTestEmitStep'
                }
                StepMetadata = New-IdleTestStepMetadata -StepTypes @('Test.IdLE.Step.Emit')
            }

            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

            $result = Invoke-IdlePlan -Plan $plan -Providers $providers

            $result.Status | Should -Be 'Completed'
            $result.Steps[0].Status | Should -Be 'Completed'
            ($result.Events | Where-Object Type -eq 'Custom').Count | Should -Be 1
        }
    }

    Context 'OnFailure behavior' {
        It 'executes OnFailureSteps when a step fails (best effort)' {
            $wfPath = New-IdleTestWorkflowFile -FileName 'onfailure.psd1' -Content @'
@{
  Name           = 'Demo - OnFailure'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{ Name = 'FailPrimary'; Type = 'Test.IdLE.Step.FailPrimary' }
    @{ Name = 'NeverRuns';   Type = 'Test.IdLE.Step.NeverRuns' }
  )
  OnFailureSteps = @(
    @{ Name = 'OnFailure1'; Type = 'Test.IdLE.Step.OnFailure1' }
  )
}
'@

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner'

            $providers = @{
                StepRegistry = @{
                    'Test.IdLE.Step.FailPrimary' = 'Invoke-IdleTestFailStep'
                    'Test.IdLE.Step.NeverRuns'   = 'Invoke-IdleTestNoopStep'
                    'Test.IdLE.Step.OnFailure1'  = 'Invoke-IdleTestEmitStep'
                }
                StepMetadata = New-IdleTestStepMetadata -StepTypes @('Test.IdLE.Step.FailPrimary', 'Test.IdLE.Step.NeverRuns', 'Test.IdLE.Step.OnFailure1')
            }

            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

            $result = Invoke-IdlePlan -Plan $plan -Providers $providers

            $result.Status | Should -Be 'Failed'
            @($result.Steps).Count | Should -Be 1
            $result.Steps[0].Name | Should -Be 'FailPrimary'

            $result.OnFailure.PSTypeNames | Should -Contain 'IdLE.OnFailureExecutionResult'
            $result.OnFailure.Status | Should -Be 'Completed'
            @($result.OnFailure.Steps).Count | Should -Be 1
            $result.OnFailure.Steps[0].Status | Should -Be 'Completed'

            $types = @($result.Events | ForEach-Object { $_.Type })
            $types | Should -Contain 'StepFailed'
            $types | Should -Contain 'OnFailureStarted'
            $types | Should -Contain 'OnFailureCompleted'

            [array]::IndexOf($types, 'StepFailed') | Should -BeLessThan ([array]::IndexOf($types, 'OnFailureStarted'))

            ($result.Events | Where-Object Type -eq 'Custom').Count | Should -Be 1
        }

        It 'continues OnFailureSteps when an OnFailure step fails (best effort)' {
            $wfPath = New-IdleTestWorkflowFile -FileName 'onfailure-partial.psd1' -Content @'
@{
  Name           = 'Demo - OnFailure Partial'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{ Name = 'FailPrimary'; Type = 'Test.IdLE.Step.FailPrimary' }
  )
  OnFailureSteps = @(
    @{ Name = 'OnFailureFail'; Type = 'Test.IdLE.Step.OnFailureFail' }
    @{ Name = 'OnFailureOk';   Type = 'Test.IdLE.Step.OnFailureOk' }
  )
}
'@

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner'

            $providers = @{
                StepRegistry = @{
                    'Test.IdLE.Step.FailPrimary'   = 'Invoke-IdleTestFailStep'
                    'Test.IdLE.Step.OnFailureFail' = 'Invoke-IdleTestFailStep'
                    'Test.IdLE.Step.OnFailureOk'   = 'Invoke-IdleTestEmitStep'
                }
                StepMetadata = New-IdleTestStepMetadata -StepTypes @('Test.IdLE.Step.FailPrimary', 'Test.IdLE.Step.OnFailureFail', 'Test.IdLE.Step.OnFailureOk')
            }

            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

            $result = Invoke-IdlePlan -Plan $plan -Providers $providers

            $result.Status | Should -Be 'Failed'
            $result.OnFailure.Status | Should -Be 'PartiallyFailed'
            @($result.OnFailure.Steps).Count | Should -Be 2
            $result.OnFailure.Steps[0].Status | Should -Be 'Failed'
            $result.OnFailure.Steps[1].Status | Should -Be 'Completed'

            ($result.Events | Where-Object Type -eq 'OnFailureStepStarted').Count | Should -Be 2
            ($result.Events | Where-Object Type -eq 'OnFailureStepFailed').Count | Should -Be 1
            ($result.Events | Where-Object Type -eq 'OnFailureStepCompleted').Count | Should -Be 1
        }

        It 'does not execute OnFailureSteps when run completes successfully' {
            $wfPath = New-IdleTestWorkflowFile -FileName 'onfailure-notrun.psd1' -Content @'
@{
  Name           = 'Demo - OnFailure NotRun'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{ Name = 'Ok'; Type = 'Test.IdLE.Step.Ok' }
  )
  OnFailureSteps = @(
    @{ Name = 'OnFailure1'; Type = 'Test.IdLE.Step.OnFailure1' }
  )
}
'@

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner'

            $providers = @{
                StepRegistry = @{
                    'Test.IdLE.Step.Ok'         = 'Invoke-IdleTestNoopStep'
                    'Test.IdLE.Step.OnFailure1' = 'Invoke-IdleTestEmitStep'
                }
                StepMetadata = New-IdleTestStepMetadata -StepTypes @('Test.IdLE.Step.Ok', 'Test.IdLE.Step.OnFailure1')
            }

            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

            $result = Invoke-IdlePlan -Plan $plan -Providers $providers

            $result.Status | Should -Be 'Completed'
            $result.OnFailure.Status | Should -Be 'NotRun'
            @($result.OnFailure.Steps).Count | Should -Be 0

            @($result.Events | Where-Object Type -like 'OnFailure*').Count | Should -Be 0
            @($result.Events | Where-Object Type -eq 'Custom').Count | Should -Be 0
        }
    }

    Context 'Planning validation' {
        It 'fails planning when a step is missing Type' {
            $wfPath = New-IdleTestWorkflowFile -FileName 'bad.psd1' -Content @'
@{
  Name           = 'Bad'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{ Name = 'NoType' }
  )
}
'@

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner'

            { New-IdlePlan -WorkflowPath $wfPath -Request $req } | Should -Throw
        }

        It 'fails planning when When schema is invalid' {
            $wfPath = New-IdleTestWorkflowFile -FileName 'bad-when.psd1' -Content @'
@{
  Name           = 'BadWhen'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'Emit'
      Type = 'IdLE.Step.EmitEvent'
      When = @{ Path = 'Plan.LifecycleEvent'; Equals = 'Joiner'; Exists = $true }
    }
  )
}
'@

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner'
            { New-IdlePlan -WorkflowPath $wfPath -Request $req } | Should -Throw
        }
    }

    Context 'Security validation' {
        It 'rejects a ScriptBlock -EventSink (security)' {
            $wfPath = New-IdleTestWorkflowFile -FileName 'joiner.psd1' -Content @'
@{
  Name           = 'Joiner - Standard'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{ Name = 'ResolveIdentity'; Type = 'Test.IdLE.Step.ResolveIdentity' }
  )
}
'@

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner'

            $providers = @{
                StepRegistry = @{
                    'Test.IdLE.Step.ResolveIdentity' = 'Invoke-IdleTestNoopStep'
                }
                StepMetadata = New-IdleTestStepMetadata -StepTypes @('Test.IdLE.Step.ResolveIdentity')
            }

            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

            $sink = { param($e) }
            { Invoke-IdlePlan -Plan $plan -Providers $providers -EventSink $sink } | Should -Throw
        }

        It 'rejects ScriptBlock step handlers in the StepRegistry (security)' {
            $wfPath = New-IdleTestWorkflowFile -FileName 'joiner.psd1' -Content @'
@{
  Name           = 'Joiner - Standard'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{ Name = 'ResolveIdentity'; Type = 'Test.IdLE.Step.ResolveIdentity' }
  )
}
'@

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner'

            $providers = @{
                StepRegistry = @{
                    'Test.IdLE.Step.ResolveIdentity' = { param($Context, $Step) }
                }
                StepMetadata = New-IdleTestStepMetadata -StepTypes @('Test.IdLE.Step.ResolveIdentity')
            }

            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

            { Invoke-IdlePlan -Plan $plan -Providers $providers } | Should -Throw
        }

        It 'rejects ScriptBlock in Plan object' {
            $plan = [pscustomobject]@{
                PSTypeName    = 'IdLE.Plan'
                CorrelationId = 'test-corr'
                Steps         = @(
                    @{
                        Name = 'TestStep'
                        Type = 'Test'
                        With = @{
                            Payload = { Write-Host 'Should not execute' }
                        }
                    }
                )
            }

            { Invoke-IdlePlan -Plan $plan } | Should -Throw '*ScriptBlocks are not allowed*'
        }

        It 'rejects ScriptBlock in Providers object' {
            $plan = [pscustomobject]@{
                PSTypeName    = 'IdLE.Plan'
                CorrelationId = 'test-corr'
                Steps         = @()
            }

            $providers = @{
                Config = @{
                    Secret = { Get-Secret }
                }
            }

            { Invoke-IdlePlan -Plan $plan -Providers $providers } | Should -Throw '*ScriptBlocks are not allowed*'
        }
    }

    Context 'Auth session acquisition' {
        It 'normalizes null options and enriches CorrelationId when acquiring an auth session' {
            $plan = [pscustomobject]@{
                PSTypeName    = 'IdLE.Plan'
                CorrelationId = 'test-corr'
                Actor         = 'test-actor'
                Steps         = @(
                    @{
                        Name = 'Acquire'
                        Type = 'Test.IdLE.Step.AcquireAuthSession'
                        With = @{
                            Name    = 'Demo'
                            Options = $null
                        }
                    }
                )
            }

            $callLog = [pscustomobject]@{
                CallCount = 0
                Name      = $null
                Options   = $null
            }

            $broker = [pscustomobject]@{}
            $acquireMethod = {
                param($Name, $Options)
                $callLog.CallCount++
                $callLog.Name = $Name
                $callLog.Options = $Options

                return [pscustomobject]@{
                    PSTypeName = 'IdLE.AuthSession'
                    Kind       = 'Test'
                }
            }.GetNewClosure()
            $null = Add-Member -InputObject $broker -MemberType ScriptMethod -Name 'AcquireAuthSession' -Value $acquireMethod -Force

            $providers = @{
                StepRegistry      = @{
                    'Test.IdLE.Step.AcquireAuthSession' = 'Invoke-IdleTestAcquireAuthSessionStep'
                }
                StepMetadata      = New-IdleTestStepMetadata -StepTypes @('Test.IdLE.Step.AcquireAuthSession')
                AuthSessionBroker = $broker
            }

            $result = Invoke-IdlePlan -Plan $plan -Providers $providers

            $result.Status | Should -Be 'Completed'
            $callLog.CallCount | Should -Be 1
            $callLog.Name | Should -Be 'Demo'

            $callLog.Options | Should -BeOfType 'hashtable'
            $callLog.Options.ContainsKey('CorrelationId') | Should -BeTrue
            $callLog.Options['CorrelationId'] | Should -Be 'test-corr'
            $callLog.Options.ContainsKey('Actor') | Should -BeTrue
            $callLog.Options['Actor'] | Should -Be 'test-actor'
        }

        It 'rejects ScriptBlocks in auth session options (security)' {
            $plan = [pscustomobject]@{
                PSTypeName    = 'IdLE.Plan'
                CorrelationId = 'test-corr'
                Steps         = @(
                    @{
                        Name = 'Acquire'
                        Type = 'Test.IdLE.Step.AcquireAuthSession'
                        With = @{
                            Name    = 'Demo'
                            Options = @{
                                Nested = @{
                                    Bad = { 'do-not-allow' }
                                }
                            }
                        }
                    }
                )
            }

            $broker = [pscustomobject]@{}
            $acquireMethod = {
                param($Name, $Options)
                return [pscustomobject]@{
                    PSTypeName = 'IdLE.AuthSession'
                    Kind       = 'Test'
                }
            }
            $null = Add-Member -InputObject $broker -MemberType ScriptMethod -Name 'AcquireAuthSession' -Value $acquireMethod -Force

            $providers = @{
                StepRegistry      = @{
                    'Test.IdLE.Step.AcquireAuthSession' = 'Invoke-IdleTestAcquireAuthSessionStep'
                }
                StepMetadata      = New-IdleTestStepMetadata -StepTypes @('Test.IdLE.Step.AcquireAuthSession')
                AuthSessionBroker = $broker
            }

            # Rejected by the generic data-only boundary on the plan before any step runs.
            { Invoke-IdlePlan -Plan $plan -Providers $providers } | Should -Throw '*ScriptBlocks are not allowed*With.Options.Nested.Bad*'
        }

        It 'calls the AuthSessionBroker and returns a completed step result (AuthSession acquisition)' {
            $plan = [pscustomobject]@{
                PSTypeName    = 'IdLE.Plan'
                CorrelationId = 'test-corr'
                Steps         = @(
                    @{
                        Name = 'Acquire'
                        Type = 'Test.IdLE.Step.AcquireAuthSession'
                        With = @{
                            Name    = 'Demo'
                            Options = @{
                                Mode     = 'Auto'
                                CacheKey = 'unit-test'
                            }
                        }
                    }
                )
            }

            $callLog = [pscustomobject]@{
                CallCount = 0
                Name      = $null
                Options   = $null
            }

            $broker = [pscustomobject]@{}
            $acquireMethod = {
                param($Name, $Options)
                $callLog.CallCount++
                $callLog.Name = $Name
                $callLog.Options = $Options

                return [pscustomobject]@{
                    PSTypeName = 'IdLE.AuthSession'
                    Kind       = 'Test'
                }
            }.GetNewClosure()
            $null = Add-Member -InputObject $broker -MemberType ScriptMethod -Name 'AcquireAuthSession' -Value $acquireMethod -Force

            $providers = @{
                StepRegistry      = @{
                    'Test.IdLE.Step.AcquireAuthSession' = 'Invoke-IdleTestAcquireAuthSessionStep'
                }
                StepMetadata      = New-IdleTestStepMetadata -StepTypes @('Test.IdLE.Step.AcquireAuthSession')
                AuthSessionBroker = $broker
            }

            $result = Invoke-IdlePlan -Plan $plan -Providers $providers

            $result.Status | Should -Be 'Completed'
            $callLog.CallCount | Should -Be 1
            $callLog.Name | Should -Be 'Demo'
            $callLog.Options['Mode'] | Should -Be 'Auto'
            $callLog.Options['CacheKey'] | Should -Be 'unit-test'
        }
    }

    Context 'Legacy step handlers' {
        It 'supports step handlers without Context parameter (backwards compatibility)' {
            $wfPath = New-IdleTestWorkflowFile -FileName 'legacy.psd1' -Content @'
@{
  Name           = 'Legacy'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{ Name = 'LegacyStep'; Type = 'Test.IdLE.Step.Legacy' }
  )
}
'@

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner'

            $providers = @{
                StepRegistry = @{
                    'Test.IdLE.Step.Legacy' = 'Invoke-IdleTestLegacyStep'
                }
                StepMetadata = New-IdleTestStepMetadata -StepTypes @('Test.IdLE.Step.Legacy')
            }

            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

            $result = Invoke-IdlePlan -Plan $plan -Providers $providers

            $result.Status | Should -Be 'Completed'
            $result.Steps[0].Status | Should -Be 'Completed'
            $result.Steps[0].Name | Should -Be 'LegacyStep'
        }
    }
}


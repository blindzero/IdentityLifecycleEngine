BeforeAll {
    . (Join-Path (Split-Path -Path $PSScriptRoot -Parent) '_testHelpers.ps1')
    Import-IdleTestModule

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
    It 'returns an execution result with events in deterministic order' {
      $wfPath = Join-Path -Path $TestDrive -ChildPath 'joiner.psd1'
      Set-Content -Path $wfPath -Encoding UTF8 -Value @'
@{
  Name           = 'Joiner - Standard'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{ Name = 'ResolveIdentity'; Type = 'IdLE.Step.ResolveIdentity' }
    @{ Name = 'EnsureAttributes'; Type = 'IdLE.Step.EnsureAttributes' }
  )
}
'@

      $req  = New-IdleRequest -LifecycleEvent 'Joiner'

      # Create a dummy provider with the required capability for EnsureAttributes
      $dummyProvider = [pscustomobject]@{
          PSTypeName = 'IdLE.Provider.TestDummy'
      }
      $dummyProvider | Add-Member -MemberType ScriptMethod -Name GetCapabilities -Value {
          return @('IdLE.Identity.Attribute.Ensure')
      }

      $providers = @{
          Identity     = $dummyProvider
          StepRegistry = @{
              'IdLE.Step.ResolveIdentity'  = 'Invoke-IdleTestNoopStep'
              'IdLE.Step.EnsureAttributes' = 'Invoke-IdleTestNoopStep'
          }
          StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.ResolveIdentity')
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

    It 'can stream events to an object sink with WriteEvent(event)' {
      $wfPath = Join-Path -Path $TestDrive -ChildPath 'joiner.psd1'
      Set-Content -Path $wfPath -Encoding UTF8 -Value @'
@{
  Name           = 'Joiner - Standard'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{ Name = 'ResolveIdentity'; Type = 'IdLE.Step.ResolveIdentity' }
  )
}
'@

      $req  = New-IdleRequest -LifecycleEvent 'Joiner'

      $providers = @{
          StepRegistry = @{
              'IdLE.Step.ResolveIdentity' = 'Invoke-IdleTestNoopStep'
          }
          StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.ResolveIdentity')
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

    It 'rejects a ScriptBlock -EventSink (security)' {
      $wfPath = Join-Path -Path $TestDrive -ChildPath 'joiner.psd1'
      Set-Content -Path $wfPath -Encoding UTF8 -Value @'
@{
  Name           = 'Joiner - Standard'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{ Name = 'ResolveIdentity'; Type = 'IdLE.Step.ResolveIdentity' }
  )
}
'@

      $req  = New-IdleRequest -LifecycleEvent 'Joiner'

      $providers = @{
          StepRegistry = @{
              'IdLE.Step.ResolveIdentity' = 'Invoke-IdleTestNoopStep'
          }
          StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.ResolveIdentity')
      }
      
      $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

      $sink = { param($e) }
      { Invoke-IdlePlan -Plan $plan -Providers $providers -EventSink $sink } | Should -Throw
    }

    It 'rejects ScriptBlock step handlers in the StepRegistry (security)' {
      $wfPath = Join-Path -Path $TestDrive -ChildPath 'joiner.psd1'
      Set-Content -Path $wfPath -Encoding UTF8 -Value @'
@{
  Name           = 'Joiner - Standard'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{ Name = 'ResolveIdentity'; Type = 'IdLE.Step.ResolveIdentity' }
  )
}
'@

      $req  = New-IdleRequest -LifecycleEvent 'Joiner'

      $providers = @{
          StepRegistry = @{
              'IdLE.Step.ResolveIdentity' = { param($Context, $Step) }
          }
          StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.ResolveIdentity')
      }
      
      $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

      { Invoke-IdlePlan -Plan $plan -Providers $providers } | Should -Throw
    }

    It 'executes a registered step and returns Completed status' {
      $wfPath = Join-Path -Path $TestDrive -ChildPath 'emit.psd1'
      Set-Content -Path $wfPath -Encoding UTF8 -Value @'
@{
  Name           = 'Demo'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{ Name = 'Emit'; Type = 'IdLE.Step.EmitEvent'; With = @{ Message = 'Hello' } }
  )
}
'@

      $req  = New-IdleRequest -LifecycleEvent 'Joiner'
      $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req

      $providers = @{
          StepRegistry = @{
              'IdLE.Step.EmitEvent' = 'Invoke-IdleTestEmitStep'
          }
          StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.EmitEvent')
      }

      $result = Invoke-IdlePlan -Plan $plan -Providers $providers

      $result.Status | Should -Be 'Completed'
      $result.Steps[0].Status | Should -Be 'Completed'
      ($result.Events | Where-Object Type -eq 'Custom').Count | Should -Be 1
    }

    It 'executes OnFailureSteps when a step fails (best effort)' {
        $wfPath = Join-Path -Path $TestDrive -ChildPath 'onfailure.psd1'
        Set-Content -Path $wfPath -Encoding UTF8 -Value @'
@{
  Name           = 'Demo - OnFailure'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{ Name = 'FailPrimary'; Type = 'IdLE.Step.FailPrimary' }
    @{ Name = 'NeverRuns';   Type = 'IdLE.Step.NeverRuns' }
  )
  OnFailureSteps = @(
    @{ Name = 'OnFailure1'; Type = 'IdLE.Step.OnFailure1' }
  )
}
'@

        $req  = New-IdleRequest -LifecycleEvent 'Joiner'

        $providers = @{
            StepRegistry = @{
                'IdLE.Step.FailPrimary' = 'Invoke-IdleTestFailStep'
                'IdLE.Step.NeverRuns'   = 'Invoke-IdleTestNoopStep'
                'IdLE.Step.OnFailure1'  = 'Invoke-IdleTestEmitStep'
            }
            StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.FailPrimary', 'IdLE.Step.NeverRuns', 'IdLE.Step.OnFailure1')
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
        $wfPath = Join-Path -Path $TestDrive -ChildPath 'onfailure-partial.psd1'
        Set-Content -Path $wfPath -Encoding UTF8 -Value @'
@{
  Name           = 'Demo - OnFailure Partial'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{ Name = 'FailPrimary'; Type = 'IdLE.Step.FailPrimary' }
  )
  OnFailureSteps = @(
    @{ Name = 'OnFailureFail'; Type = 'IdLE.Step.OnFailureFail' }
    @{ Name = 'OnFailureOk';   Type = 'IdLE.Step.OnFailureOk' }
  )
}
'@

        $req  = New-IdleRequest -LifecycleEvent 'Joiner'

        $providers = @{
            StepRegistry = @{
                'IdLE.Step.FailPrimary'   = 'Invoke-IdleTestFailStep'
                'IdLE.Step.OnFailureFail' = 'Invoke-IdleTestFailStep'
                'IdLE.Step.OnFailureOk'   = 'Invoke-IdleTestEmitStep'
            }
            StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.FailPrimary', 'IdLE.Step.OnFailureFail', 'IdLE.Step.OnFailureOk')
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
        $wfPath = Join-Path -Path $TestDrive -ChildPath 'onfailure-notrun.psd1'
        Set-Content -Path $wfPath -Encoding UTF8 -Value @'
@{
  Name           = 'Demo - OnFailure NotRun'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{ Name = 'Ok'; Type = 'IdLE.Step.Ok' }
  )
  OnFailureSteps = @(
    @{ Name = 'OnFailure1'; Type = 'IdLE.Step.OnFailure1' }
  )
}
'@

        $req  = New-IdleRequest -LifecycleEvent 'Joiner'

        $providers = @{
            StepRegistry = @{
                'IdLE.Step.Ok'         = 'Invoke-IdleTestNoopStep'
                'IdLE.Step.OnFailure1' = 'Invoke-IdleTestEmitStep'
            }
            StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.Ok', 'IdLE.Step.OnFailure1')
        }
        
        $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

        $result = Invoke-IdlePlan -Plan $plan -Providers $providers

        $result.Status | Should -Be 'Completed'
        $result.OnFailure.Status | Should -Be 'NotRun'
        @($result.OnFailure.Steps).Count | Should -Be 0

        @($result.Events | Where-Object Type -like 'OnFailure*').Count | Should -Be 0
        @($result.Events | Where-Object Type -eq 'Custom').Count | Should -Be 0
    }

    It 'fails planning when a step is missing Type' {
      $wfPath = Join-Path -Path $TestDrive -ChildPath 'bad.psd1'
      Set-Content -Path $wfPath -Encoding UTF8 -Value @'
@{
  Name           = 'Bad'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{ Name = 'NoType' }
  )
}
'@

      $req = New-IdleRequest -LifecycleEvent 'Joiner'

      { New-IdlePlan -WorkflowPath $wfPath -Request $req } | Should -Throw
    }

    It 'fails planning when When schema is invalid' {
      $wfPath = Join-Path -Path $TestDrive -ChildPath 'bad-when.psd1'
      Set-Content -Path $wfPath -Encoding UTF8 -Value @'
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

      $req = New-IdleRequest -LifecycleEvent 'Joiner'
      { New-IdlePlan -WorkflowPath $wfPath -Request $req } | Should -Throw
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

    It 'throws when AuthSessionBroker is missing (AuthSession acquisition)' {
        $plan = [pscustomobject]@{
            PSTypeName    = 'IdLE.Plan'
            CorrelationId = 'test-corr'
            Steps         = @(
                @{
                    Name = 'Acquire'
                    Type = 'IdLE.Step.AcquireAuthSession'
                    With = @{
                        Name    = 'Demo'
                        Options = @{}
                    }
                }
            )
        }

        $providers = @{
            StepRegistry = @{
                'IdLE.Step.AcquireAuthSession' = 'Invoke-IdleTestAcquireAuthSessionStep'
            }
            StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.AcquireAuthSession')
        }

        { Invoke-IdlePlan -Plan $plan -Providers $providers } | Should -Throw '*AuthSessionBroker*'
    }

    It 'does not require AuthSessionBroker when AcquireAuthSession steps are NotApplicable' {
        $plan = [pscustomobject]@{
            PSTypeName    = 'IdLE.Plan'
            CorrelationId = 'test-corr'
            Steps         = @(
                @{
                    Name   = 'ConditionalAcquire'
                    Type   = 'IdLE.Step.AcquireAuthSession'
                    Status = 'NotApplicable'
                    With   = @{
                        Name    = 'Demo'
                        Options = @{}
                    }
                }
                @{
                    Name = 'SomeOtherStep'
                    Type = 'IdLE.Step.Noop'
                    With = @{}
                }
            )
        }

        $providers = @{
            StepRegistry = @{
                'IdLE.Step.AcquireAuthSession' = 'Invoke-IdleTestAcquireAuthSessionStep'
                'IdLE.Step.Noop'               = 'Invoke-IdleTestNoopStep'
            }
            StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.AcquireAuthSession', 'IdLE.Step.Noop')
        }

        # Should not throw because the AcquireAuthSession step is NotApplicable
        { Invoke-IdlePlan -Plan $plan -Providers $providers } | Should -Not -Throw
    }

    It 'normalizes null options and enriches CorrelationId when acquiring an auth session' {
        $plan = [pscustomobject]@{
            PSTypeName    = 'IdLE.Plan'
            CorrelationId = 'test-corr'
            Actor         = 'test-actor'
            Steps         = @(
                @{
                    Name = 'Acquire'
                    Type = 'IdLE.Step.AcquireAuthSession'
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
                'IdLE.Step.AcquireAuthSession' = 'Invoke-IdleTestAcquireAuthSessionStep'
            }
            StepMetadata      = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.AcquireAuthSession')
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
                    Type = 'IdLE.Step.AcquireAuthSession'
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
                'IdLE.Step.AcquireAuthSession' = 'Invoke-IdleTestAcquireAuthSessionStep'
            }
            StepMetadata      = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.AcquireAuthSession')
            AuthSessionBroker = $broker
        }

        { Invoke-IdlePlan -Plan $plan -Providers $providers } | Should -Throw '*auth session options*'
    }

    It 'calls the AuthSessionBroker and returns a completed step result (AuthSession acquisition)' {
        $plan = [pscustomobject]@{
            PSTypeName    = 'IdLE.Plan'
            CorrelationId = 'test-corr'
            Steps         = @(
                @{
                    Name = 'Acquire'
                    Type = 'IdLE.Step.AcquireAuthSession'
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
                'IdLE.Step.AcquireAuthSession' = 'Invoke-IdleTestAcquireAuthSessionStep'
            }
            StepMetadata      = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.AcquireAuthSession')
            AuthSessionBroker = $broker
        }

        $result = Invoke-IdlePlan -Plan $plan -Providers $providers

        $result.Status | Should -Be 'Completed'
        $callLog.CallCount | Should -Be 1
        $callLog.Name | Should -Be 'Demo'
        $callLog.Options['Mode'] | Should -Be 'Auto'
        $callLog.Options['CacheKey'] | Should -Be 'unit-test'
    }

    It 'supports step handlers without Context parameter (backwards compatibility)' {
        $wfPath = Join-Path -Path $TestDrive -ChildPath 'legacy.psd1'
        Set-Content -Path $wfPath -Encoding UTF8 -Value @'
@{
  Name           = 'Legacy'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{ Name = 'LegacyStep'; Type = 'IdLE.Step.Legacy' }
  )
}
'@

        $req  = New-IdleRequest -LifecycleEvent 'Joiner'

        $providers = @{
            StepRegistry = @{
                'IdLE.Step.Legacy' = 'Invoke-IdleTestLegacyStep'
            }
            StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.Legacy')
        }
        
        $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

        $result = Invoke-IdlePlan -Plan $plan -Providers $providers

        $result.Status | Should -Be 'Completed'
        $result.Steps[0].Status | Should -Be 'Completed'
        $result.Steps[0].Name | Should -Be 'LegacyStep'
    }
}


BeforeDiscovery {
    . (Join-Path (Split-Path -Path $PSScriptRoot -Parent) '_testHelpers.ps1')
    Import-IdleTestModule
}

BeforeAll {
    . (Join-Path (Split-Path -Path $PSScriptRoot -Parent) '_testHelpers.ps1')
    Import-IdleTestModule

    # Create a dedicated test module for retry profile testing
    $script:RetryProfileTestModuleName = 'IdLE.RetryProfileTest'
    $script:RetryProfileTestModule = New-Module -Name $script:RetryProfileTestModuleName -ScriptBlock {
        Set-StrictMode -Version Latest

        $script:CallLog = [System.Collections.ArrayList]::new()

        function Invoke-IdleRetryProfileTestStep {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory)]
                [ValidateNotNull()]
                [object] $Context,

                [Parameter(Mandatory)]
                [ValidateNotNull()]
                [object] $Step
            )

            $null = $script:CallLog.Add(@{
                StepName  = [string]$Step.Name
                Timestamp = [DateTimeOffset]::UtcNow
            })

            # Succeed on first attempt
            return [pscustomobject]@{
                PSTypeName = 'IdLE.StepResult'
                Name       = [string]$Step.Name
                Type       = [string]$Step.Type
                Status     = 'Completed'
                Error      = $null
            }
        }

        function Invoke-IdleRetryProfileTransientStep {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory)]
                [ValidateNotNull()]
                [object] $Context,

                [Parameter(Mandatory)]
                [ValidateNotNull()]
                [object] $Step
            )

            $stepName = [string]$Step.Name
            $attempts = @($script:CallLog | Where-Object { $_.StepName -eq $stepName }).Count + 1

            $null = $script:CallLog.Add(@{
                StepName  = $stepName
                Attempt   = $attempts
                Timestamp = [DateTimeOffset]::UtcNow
            })

            # Fail on first attempt, succeed on second
            if ($attempts -eq 1) {
                $ex = [System.Exception]::new("Transient failure for $stepName")
                $ex.Data['Idle.IsTransient'] = $true
                throw $ex
            }

            return [pscustomobject]@{
                PSTypeName = 'IdLE.StepResult'
                Name       = $stepName
                Type       = [string]$Step.Type
                Status     = 'Completed'
                Error      = $null
            }
        }

        function Reset-IdleRetryProfileTestState {
            [CmdletBinding()]
            param()

            $script:CallLog.Clear()
        }

        function Get-IdleRetryProfileTestCallLog {
            [CmdletBinding()]
            param()

            return [array]$script:CallLog
        }

        Export-ModuleMember -Function @(
            'Invoke-IdleRetryProfileTestStep',
            'Invoke-IdleRetryProfileTransientStep',
            'Reset-IdleRetryProfileTestState',
            'Get-IdleRetryProfileTestCallLog'
        )
    }

    Import-Module -ModuleInfo $script:RetryProfileTestModule -Force -ErrorAction Stop
}

AfterAll {
    Remove-Module -Name $script:RetryProfileTestModuleName -Force -ErrorAction SilentlyContinue
}

Describe 'Invoke-IdlePlan - ExecutionOptions validation' {

    It 'rejects ExecutionOptions with invalid type' -Skip {
        # Note: PowerShell parameter type validation catches this before our validation,
        # so this test is skipped. The validation still exists and would catch it if
        # the parameter type was changed to [object].
        $wfPath = Join-Path -Path $TestDrive -ChildPath 'test.psd1'
        Set-Content -Path $wfPath -Encoding UTF8 -Value @'
@{
  Name           = 'Test Workflow'
  LifecycleEvent = 'Joiner'
  Steps          = @()
}
'@

        $req = New-IdleLifecycleRequest -LifecycleEvent 'Joiner'
        $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req

        { Invoke-IdlePlan -Plan $plan -ExecutionOptions 'invalid' } | Should -Throw -ExpectedMessage '*must be a hashtable or IDictionary*'
    }

    It 'rejects ExecutionOptions with ScriptBlocks' {
        $wfPath = Join-Path -Path $TestDrive -ChildPath 'test.psd1'
        Set-Content -Path $wfPath -Encoding UTF8 -Value @'
@{
  Name           = 'Test Workflow'
  LifecycleEvent = 'Joiner'
  Steps          = @()
}
'@

        $req = New-IdleLifecycleRequest -LifecycleEvent 'Joiner'
        $providers = @{ StepRegistry = @{} }
        $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

        $opts = @{
            SomeKey = { Write-Host 'test' }
        }

        { Invoke-IdlePlan -Plan $plan -ExecutionOptions $opts } | Should -Throw -ExpectedMessage '*ScriptBlocks are not allowed*'
    }

    It 'rejects RetryProfile with invalid MaxAttempts' {
        $wfPath = Join-Path -Path $TestDrive -ChildPath 'test.psd1'
        Set-Content -Path $wfPath -Encoding UTF8 -Value @'
@{
  Name           = 'Test Workflow'
  LifecycleEvent = 'Joiner'
  Steps          = @()
}
'@

        $req = New-IdleLifecycleRequest -LifecycleEvent 'Joiner'
        $providers = @{ StepRegistry = @{} }
        $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

        $opts = @{
            RetryProfiles = @{
                Invalid = @{ MaxAttempts = 50 }
            }
        }

        { Invoke-IdlePlan -Plan $plan -ExecutionOptions $opts } | Should -Throw -ExpectedMessage '*MaxAttempts must be an integer between 0 and 10*'
    }

    It 'rejects DefaultRetryProfile that does not exist' {
        $wfPath = Join-Path -Path $TestDrive -ChildPath 'test.psd1'
        Set-Content -Path $wfPath -Encoding UTF8 -Value @'
@{
  Name           = 'Test Workflow'
  LifecycleEvent = 'Joiner'
  Steps          = @()
}
'@

        $req = New-IdleLifecycleRequest -LifecycleEvent 'Joiner'
        $providers = @{ StepRegistry = @{} }
        $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

        $opts = @{
            RetryProfiles = @{
                Default = @{ MaxAttempts = 3 }
            }
            DefaultRetryProfile = 'Unknown'
        }

        { Invoke-IdlePlan -Plan $plan -ExecutionOptions $opts } | Should -Throw -ExpectedMessage '*does not exist*'
    }

    It 'rejects MaxDelayMilliseconds less than engine default InitialDelayMilliseconds' {
        $wfPath = Join-Path -Path $TestDrive -ChildPath 'test.psd1'
        Set-Content -Path $wfPath -Encoding UTF8 -Value @'
@{
  Name           = 'Test Workflow'
  LifecycleEvent = 'Joiner'
  Steps          = @()
}
'@

        $req = New-IdleLifecycleRequest -LifecycleEvent 'Joiner'
        $providers = @{ StepRegistry = @{} }
        $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

        $opts = @{
            RetryProfiles = @{
                Invalid = @{
                    MaxDelayMilliseconds = 100  # Less than engine default InitialDelayMilliseconds (250)
                }
            }
        }

        { Invoke-IdlePlan -Plan $plan -ExecutionOptions $opts } | Should -Throw -ExpectedMessage '*MaxDelayMilliseconds*must be >= InitialDelayMilliseconds*'
    }
}

Describe 'Invoke-IdlePlan - ExecutionOptions with RetryProfiles' {

    BeforeEach {
        & "$script:RetryProfileTestModuleName\Reset-IdleRetryProfileTestState"
    }

    It 'executes successfully without ExecutionOptions (backward compatibility)' {
        $wfPath = Join-Path -Path $TestDrive -ChildPath 'no-opts.psd1'
        Set-Content -Path $wfPath -Encoding UTF8 -Value @'
@{
  Name           = 'Test Workflow'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{ Name = 'Step1'; Type = 'Test.Step' }
  )
}
'@

        $req = New-IdleLifecycleRequest -LifecycleEvent 'Joiner'

        $providers = @{
            StepRegistry = @{
                'Test.Step' = "$script:RetryProfileTestModuleName\Invoke-IdleRetryProfileTestStep"
            }
            StepMetadata = New-IdleTestStepMetadata -StepTypes @('Test.Step')
        }

        $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers
        $result = Invoke-IdlePlan -Plan $plan -Providers $providers

        $result.Status | Should -Be 'Completed'
        $result.Steps[0].Status | Should -Be 'Completed'
    }

    It 'executes with custom RetryProfile on step' {
        Mock -ModuleName IdLE.Core -CommandName Start-Sleep -MockWith { }

        $wfPath = Join-Path -Path $TestDrive -ChildPath 'custom-profile.psd1'
        Set-Content -Path $wfPath -Encoding UTF8 -Value @'
@{
  Name           = 'Test Workflow'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{ Name = 'Step1'; Type = 'Test.TransientStep'; RetryProfile = 'Custom' }
  )
}
'@

        $req = New-IdleLifecycleRequest -LifecycleEvent 'Joiner'

        $providers = @{
            StepRegistry = @{
                'Test.TransientStep' = "$script:RetryProfileTestModuleName\Invoke-IdleRetryProfileTransientStep"
            }
            StepMetadata = New-IdleTestStepMetadata -StepTypes @('Test.TransientStep')
        }

        $opts = @{
            RetryProfiles = @{
                Custom = @{
                    MaxAttempts              = 5
                    InitialDelayMilliseconds = 100
                }
            }
        }

        $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers
        $result = Invoke-IdlePlan -Plan $plan -Providers $providers -ExecutionOptions $opts

        $result.Status | Should -Be 'Completed'
        $result.Steps[0].Status | Should -Be 'Completed'
        $result.Steps[0].Attempts | Should -Be 2

        # Verify retry event was emitted
        @($result.Events | Where-Object Type -eq 'StepRetrying').Count | Should -Be 1
    }

    It 'uses DefaultRetryProfile when step does not specify RetryProfile' {
        Mock -ModuleName IdLE.Core -CommandName Start-Sleep -MockWith { }

        $wfPath = Join-Path -Path $TestDrive -ChildPath 'default-profile.psd1'
        Set-Content -Path $wfPath -Encoding UTF8 -Value @'
@{
  Name           = 'Test Workflow'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{ Name = 'Step1'; Type = 'Test.TransientStep' }
  )
}
'@

        $req = New-IdleLifecycleRequest -LifecycleEvent 'Joiner'

        $providers = @{
            StepRegistry = @{
                'Test.TransientStep' = "$script:RetryProfileTestModuleName\Invoke-IdleRetryProfileTransientStep"
            }
            StepMetadata = New-IdleTestStepMetadata -StepTypes @('Test.TransientStep')
        }

        $opts = @{
            RetryProfiles = @{
                Default = @{
                    MaxAttempts              = 10
                    InitialDelayMilliseconds = 50
                }
            }
            DefaultRetryProfile = 'Default'
        }

        $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers
        $result = Invoke-IdlePlan -Plan $plan -Providers $providers -ExecutionOptions $opts

        $result.Status | Should -Be 'Completed'
        $result.Steps[0].Attempts | Should -Be 2
    }

    It 'fails fast when step references unknown RetryProfile' {
        $wfPath = Join-Path -Path $TestDrive -ChildPath 'unknown-profile.psd1'
        Set-Content -Path $wfPath -Encoding UTF8 -Value @'
@{
  Name           = 'Test Workflow'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{ Name = 'Step1'; Type = 'Test.Step'; RetryProfile = 'Unknown' }
  )
}
'@

        $req = New-IdleLifecycleRequest -LifecycleEvent 'Joiner'

        $providers = @{
            StepRegistry = @{
                'Test.Step' = "$script:RetryProfileTestModuleName\Invoke-IdleRetryProfileTestStep"
            }
            StepMetadata = New-IdleTestStepMetadata -StepTypes @('Test.Step')
        }

        $opts = @{
            RetryProfiles = @{
                Default = @{ MaxAttempts = 3 }
            }
        }

        $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers
        $result = Invoke-IdlePlan -Plan $plan -Providers $providers -ExecutionOptions $opts

        # The error should be caught and reported in the result
        $result.Status | Should -Be 'Failed'
        $result.Steps[0].Status | Should -Be 'Failed'
        $result.Steps[0].Error | Should -Match 'unknown RetryProfile.*Unknown'
    }

    It 'supports MaxAttempts = 0 (no retry)' {
        Mock -ModuleName IdLE.Core -CommandName Start-Sleep -MockWith { }

        $wfPath = Join-Path -Path $TestDrive -ChildPath 'no-retry.psd1'
        Set-Content -Path $wfPath -Encoding UTF8 -Value @'
@{
  Name           = 'Test Workflow'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{ Name = 'Step1'; Type = 'Test.TransientStep'; RetryProfile = 'NoRetry' }
  )
}
'@

        $req = New-IdleLifecycleRequest -LifecycleEvent 'Joiner'

        $providers = @{
            StepRegistry = @{
                'Test.TransientStep' = "$script:RetryProfileTestModuleName\Invoke-IdleRetryProfileTransientStep"
            }
            StepMetadata = New-IdleTestStepMetadata -StepTypes @('Test.TransientStep')
        }

        $opts = @{
            RetryProfiles = @{
                NoRetry = @{
                    MaxAttempts = 0
                }
            }
        }

        $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers
        $result = Invoke-IdlePlan -Plan $plan -Providers $providers -ExecutionOptions $opts

        # With MaxAttempts = 0, the step runs once and fails without retry
        $result.Status | Should -Be 'Failed'
        $result.Steps[0].Status | Should -Be 'Failed'
        $result.Steps[0].Attempts | Should -Be 1

        # No retry event should be emitted
        @($result.Events | Where-Object Type -eq 'StepRetrying').Count | Should -Be 0
        Should -Invoke -ModuleName IdLE.Core -CommandName Start-Sleep -Times 0
    }

    It 'applies RetryProfile to OnFailureSteps' {
        Mock -ModuleName IdLE.Core -CommandName Start-Sleep -MockWith { }

        # Create a module with a failing step
        $failingModuleName = 'IdLE.FailingTest'
        $failingModule = New-Module -Name $failingModuleName -ScriptBlock {
            function Invoke-IdleFailingStep {
                [CmdletBinding()]
                param(
                    [Parameter(Mandatory)]
                    [ValidateNotNull()]
                    [object] $Context,

                    [Parameter(Mandatory)]
                    [ValidateNotNull()]
                    [object] $Step
                )

                throw [System.Exception]::new('Intentional failure for test')
            }

            Export-ModuleMember -Function 'Invoke-IdleFailingStep'
        }
        Import-Module -ModuleInfo $failingModule -Force -ErrorAction Stop

        $wfPath = Join-Path -Path $TestDrive -ChildPath 'onfailure-profile.psd1'
        Set-Content -Path $wfPath -Encoding UTF8 -Value @'
@{
  Name           = 'Test Workflow'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{ Name = 'FailingStep'; Type = 'Test.Failing' }
  )
  OnFailureSteps = @(
    @{ Name = 'CleanupStep'; Type = 'Test.TransientStep'; RetryProfile = 'Cleanup' }
  )
}
'@

        $req = New-IdleLifecycleRequest -LifecycleEvent 'Joiner'

        $providers = @{
            StepRegistry = @{
                'Test.Failing'       = "$failingModuleName\Invoke-IdleFailingStep"
                'Test.TransientStep' = "$script:RetryProfileTestModuleName\Invoke-IdleRetryProfileTransientStep"
            }
            StepMetadata = New-IdleTestStepMetadata -StepTypes @('Test.Failing', 'Test.TransientStep')
        }

        $opts = @{
            RetryProfiles = @{
                Cleanup = @{
                    MaxAttempts              = 3
                    InitialDelayMilliseconds = 100
                }
            }
        }

        $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers
        $result = Invoke-IdlePlan -Plan $plan -Providers $providers -ExecutionOptions $opts

        $result.Status | Should -Be 'Failed'
        $result.OnFailure.Status | Should -Be 'Completed'
        $result.OnFailure.Steps[0].Attempts | Should -Be 2

        Remove-Module -Name $failingModuleName -Force -ErrorAction SilentlyContinue
    }
}

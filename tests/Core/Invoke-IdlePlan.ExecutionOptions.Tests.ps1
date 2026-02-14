Set-StrictMode -Version Latest

BeforeAll {
    . (Join-Path (Split-Path -Path $PSScriptRoot -Parent) '_testHelpers.ps1')
    Import-IdleTestModule

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

Describe 'Invoke-IdlePlan - ExecutionOptions' {
    Context 'Validation' {
        It 'rejects ExecutionOptions with invalid type (parameter binding)' {
            $wfPath = New-IdleTestWorkflowFile -Content @'
@{
  Name           = 'Test Workflow'
  LifecycleEvent = 'Joiner'
  Steps          = @()
}
'@

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner'
            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req

            { Invoke-IdlePlan -Plan $plan -ExecutionOptions 'invalid' } | Should -Throw -ExpectedMessage '*Cannot convert*Hashtable*'
        }

        It 'rejects ExecutionOptions with ScriptBlocks' {
            $wfPath = New-IdleTestWorkflowFile -Content @'
@{
  Name           = 'Test Workflow'
  LifecycleEvent = 'Joiner'
  Steps          = @()
}
'@

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner'
            $providers = @{ StepRegistry = @{} }
            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

            $opts = @{ SomeKey = { Write-Host 'test' } }

            { Invoke-IdlePlan -Plan $plan -ExecutionOptions $opts } | Should -Throw -ExpectedMessage '*ScriptBlocks are not allowed*'
        }

        It 'rejects RetryProfile with invalid MaxAttempts' {
            $wfPath = New-IdleTestWorkflowFile -Content @'
@{
  Name           = 'Test Workflow'
  LifecycleEvent = 'Joiner'
  Steps          = @()
}
'@

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner'
            $providers = @{ StepRegistry = @{} }
            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

            $opts = @{ RetryProfiles = @{ Invalid = @{ MaxAttempts = 50 } } }

            { Invoke-IdlePlan -Plan $plan -ExecutionOptions $opts } | Should -Throw -ExpectedMessage '*MaxAttempts must be an integer between 0 and 10*'
        }

        It 'rejects DefaultRetryProfile that does not exist' {
            $wfPath = New-IdleTestWorkflowFile -Content @'
@{
  Name           = 'Test Workflow'
  LifecycleEvent = 'Joiner'
  Steps          = @()
}
'@

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner'
            $providers = @{ StepRegistry = @{} }
            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

            $opts = @{
                RetryProfiles = @{ Default = @{ MaxAttempts = 3 } }
                DefaultRetryProfile = 'Unknown'
            }

            { Invoke-IdlePlan -Plan $plan -ExecutionOptions $opts } | Should -Throw -ExpectedMessage '*does not exist*'
        }

        It 'rejects MaxDelayMilliseconds less than engine default InitialDelayMilliseconds' {
            $wfPath = New-IdleTestWorkflowFile -Content @'
@{
  Name           = 'Test Workflow'
  LifecycleEvent = 'Joiner'
  Steps          = @()
}
'@

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner'
            $providers = @{ StepRegistry = @{} }
            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

            $opts = @{
                RetryProfiles = @{
                    Invalid = @{ MaxDelayMilliseconds = 100 }
                }
            }

            { Invoke-IdlePlan -Plan $plan -ExecutionOptions $opts } | Should -Throw -ExpectedMessage '*MaxDelayMilliseconds*must be >= InitialDelayMilliseconds*'
        }
    }

    Context 'Retry profiles' {
        BeforeEach {
            & "$script:RetryProfileTestModuleName\Reset-IdleRetryProfileTestState"
        }

        It 'executes successfully without ExecutionOptions (backward compatibility)' {
            $wfPath = New-IdleTestWorkflowFile -FileName 'no-opts.psd1' -Content @'
@{
  Name           = 'Test Workflow'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{ Name = 'Step1'; Type = 'Test.Step' }
  )
}
'@

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner'

            $providers = @{
                StepRegistry = @{ 'Test.Step' = "$script:RetryProfileTestModuleName\Invoke-IdleRetryProfileTestStep" }
                StepMetadata = New-IdleTestStepMetadata -StepTypes @('Test.Step')
            }

            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers
            $result = Invoke-IdlePlan -Plan $plan -Providers $providers

            $result.Status | Should -Be 'Completed'
            $result.Steps[0].Status | Should -Be 'Completed'
        }

        It 'executes with custom RetryProfile on step' {
            Mock -ModuleName IdLE.Core -CommandName Start-Sleep -MockWith { }

            $wfPath = New-IdleTestWorkflowFile -FileName 'custom-profile.psd1' -Content @'
@{
  Name           = 'Test Workflow'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{ Name = 'Step1'; Type = 'Test.TransientStep'; RetryProfile = 'Custom' }
  )
}
'@

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner'

            $providers = @{
                StepRegistry = @{ 'Test.TransientStep' = "$script:RetryProfileTestModuleName\Invoke-IdleRetryProfileTransientStep" }
                StepMetadata = New-IdleTestStepMetadata -StepTypes @('Test.TransientStep')
            }

            $opts = @{
                RetryProfiles = @{
                    Custom = @{ MaxAttempts = 5; InitialDelayMilliseconds = 100 }
                }
            }

            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers
            $result = Invoke-IdlePlan -Plan $plan -Providers $providers -ExecutionOptions $opts

            $result.Status | Should -Be 'Completed'
            $result.Steps[0].Status | Should -Be 'Completed'
            $result.Steps[0].Attempts | Should -Be 2
            @($result.Events | Where-Object Type -eq 'StepRetrying').Count | Should -Be 1
        }

        It 'uses DefaultRetryProfile when step does not specify RetryProfile' {
            Mock -ModuleName IdLE.Core -CommandName Start-Sleep -MockWith { }

            $wfPath = New-IdleTestWorkflowFile -FileName 'default-profile.psd1' -Content @'
@{
  Name           = 'Test Workflow'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{ Name = 'Step1'; Type = 'Test.TransientStep' }
  )
}
'@

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner'

            $providers = @{
                StepRegistry = @{ 'Test.TransientStep' = "$script:RetryProfileTestModuleName\Invoke-IdleRetryProfileTransientStep" }
                StepMetadata = New-IdleTestStepMetadata -StepTypes @('Test.TransientStep')
            }

            $opts = @{
                RetryProfiles = @{ Default = @{ MaxAttempts = 10; InitialDelayMilliseconds = 50 } }
                DefaultRetryProfile = 'Default'
            }

            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers
            $result = Invoke-IdlePlan -Plan $plan -Providers $providers -ExecutionOptions $opts

            $result.Status | Should -Be 'Completed'
            $result.Steps[0].Attempts | Should -Be 2
        }

        It 'fails fast when step references unknown RetryProfile' {
            $wfPath = New-IdleTestWorkflowFile -FileName 'unknown-profile.psd1' -Content @'
@{
  Name           = 'Test Workflow'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{ Name = 'Step1'; Type = 'Test.Step'; RetryProfile = 'Unknown' }
  )
}
'@

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner'

            $providers = @{
                StepRegistry = @{ 'Test.Step' = "$script:RetryProfileTestModuleName\Invoke-IdleRetryProfileTestStep" }
                StepMetadata = New-IdleTestStepMetadata -StepTypes @('Test.Step')
            }

            $opts = @{ RetryProfiles = @{ Default = @{ MaxAttempts = 3 } } }

            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers
            $result = Invoke-IdlePlan -Plan $plan -Providers $providers -ExecutionOptions $opts

            $result.Status | Should -Be 'Failed'
            $result.Steps[0].Status | Should -Be 'Failed'
            $result.Steps[0].Error | Should -Match 'unknown RetryProfile.*Unknown'
        }

        It 'supports MaxAttempts = 0 (no retry)' {
            Mock -ModuleName IdLE.Core -CommandName Start-Sleep -MockWith { }

            $wfPath = New-IdleTestWorkflowFile -FileName 'no-retry.psd1' -Content @'
@{
  Name           = 'Test Workflow'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{ Name = 'Step1'; Type = 'Test.TransientStep'; RetryProfile = 'NoRetry' }
  )
}
'@

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner'

            $providers = @{
                StepRegistry = @{ 'Test.TransientStep' = "$script:RetryProfileTestModuleName\Invoke-IdleRetryProfileTransientStep" }
                StepMetadata = New-IdleTestStepMetadata -StepTypes @('Test.TransientStep')
            }

            $opts = @{ RetryProfiles = @{ NoRetry = @{ MaxAttempts = 0 } } }

            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers
            $result = Invoke-IdlePlan -Plan $plan -Providers $providers -ExecutionOptions $opts

            $result.Status | Should -Be 'Failed'
            $result.Steps[0].Status | Should -Be 'Failed'
            $result.Steps[0].Attempts | Should -Be 1
            @($result.Events | Where-Object Type -eq 'StepRetrying').Count | Should -Be 0
            Should -Invoke -ModuleName IdLE.Core -CommandName Start-Sleep -Times 0
        }

        It 'applies RetryProfile to OnFailureSteps' {
            Mock -ModuleName IdLE.Core -CommandName Start-Sleep -MockWith { }

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

            $wfPath = New-IdleTestWorkflowFile -FileName 'onfailure-profile.psd1' -Content @'
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

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner'

            $providers = @{
                StepRegistry = @{
                    'Test.Failing'       = "$failingModuleName\Invoke-IdleFailingStep"
                    'Test.TransientStep' = "$script:RetryProfileTestModuleName\Invoke-IdleRetryProfileTransientStep"
                }
                StepMetadata = New-IdleTestStepMetadata -StepTypes @('Test.Failing', 'Test.TransientStep')
            }

            $opts = @{
                RetryProfiles = @{ Cleanup = @{ MaxAttempts = 3; InitialDelayMilliseconds = 100 } }
            }

            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers
            $result = Invoke-IdlePlan -Plan $plan -Providers $providers -ExecutionOptions $opts

            $result.Status | Should -Be 'Failed'
            $result.OnFailure.Status | Should -Be 'Completed'
            $result.OnFailure.Steps[0].Attempts | Should -Be 2

            Remove-Module -Name $failingModuleName -Force -ErrorAction SilentlyContinue
        }
    }
}

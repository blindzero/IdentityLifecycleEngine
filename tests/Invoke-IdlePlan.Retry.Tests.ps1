BeforeDiscovery {
    . (Join-Path $PSScriptRoot '_testHelpers.ps1')
    Import-IdleTestModule
}

BeforeAll {
    . (Join-Path $PSScriptRoot '_testHelpers.ps1')
    Import-IdleTestModule
    
    # Create a dedicated, ephemeral test module that exports the step handlers.
    # This avoids global scope pollution while ensuring the engine can resolve
    # handler names deterministically via module-qualified command names.
    $script:RetryTestModuleName = 'IdLE.RetryTest'
    $script:RetryTestModule = New-Module -Name $script:RetryTestModuleName -ScriptBlock {
        Set-StrictMode -Version Latest

        $script:TransientCallCount = 0

        function Invoke-IdleRetryTestTransientStep {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory)]
                [ValidateNotNull()]
                [object] $Context,

                [Parameter(Mandatory)]
                [ValidateNotNull()]
                [object] $Step
            )

            $script:TransientCallCount++

            if ($script:TransientCallCount -eq 1) {
                $ex = [System.Exception]::new('Transient failure (simulated)')
                $ex.Data['Idle.IsTransient'] = $true
                throw $ex
            }

            return [pscustomobject]@{
                PSTypeName = 'IdLE.StepResult'
                Name       = [string]$Step.Name
                Type       = [string]$Step.Type
                Status     = 'Completed'
                Error      = $null
            }
        }

        function Invoke-IdleRetryTestNonTransientStep {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory)]
                [ValidateNotNull()]
                [object] $Context,

                [Parameter(Mandatory)]
                [ValidateNotNull()]
                [object] $Step
            )

            throw [System.Exception]::new('Non-transient failure (simulated)')
        }

        function Reset-IdleRetryTestState {
            [CmdletBinding()]
            param()

            $script:TransientCallCount = 0
        }

        function Get-IdleRetryTestTransientCallCount {
            [CmdletBinding()]
            param()

            return [int]$script:TransientCallCount
        }

        Export-ModuleMember -Function @(
            'Invoke-IdleRetryTestTransientStep',
            'Invoke-IdleRetryTestNonTransientStep',
            'Reset-IdleRetryTestState',
            'Get-IdleRetryTestTransientCallCount'
        )
    }

    Import-Module -ModuleInfo $script:RetryTestModule -Force -ErrorAction Stop
}

AfterAll {
    # Remove the ephemeral module.
    Remove-Module -Name $script:RetryTestModuleName -Force -ErrorAction SilentlyContinue
}

Describe 'Invoke-IdlePlan - safe retries for transient failures (fail-fast)' {

    BeforeEach {
        & "$script:RetryTestModuleName\Reset-IdleRetryTestState"
    }

    It 'retries a step when the error is explicitly marked transient and then succeeds' {
        Mock -ModuleName IdLE.Core -CommandName Start-Sleep -MockWith { }

        $wfPath = Join-Path -Path $TestDrive -ChildPath 'retry-transient.psd1'
        Set-Content -Path $wfPath -Encoding UTF8 -Value @'
@{
  Name           = 'Retry Transient Demo'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{ Name = 'TransientStep'; Type = 'IdLE.Step.Transient' }
  )
}
'@

        $req  = New-IdleLifecycleRequest -LifecycleEvent 'Joiner'

        $providers = @{
            StepRegistry = @{
                'IdLE.Step.Transient' = "$script:RetryTestModuleName\Invoke-IdleRetryTestTransientStep"
            }
            StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.Transient')
        }
        
        $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

        $result = Invoke-IdlePlan -Plan $plan -Providers $providers

        $result.Status | Should -Be 'Completed'
        $result.Steps[0].Status | Should -Be 'Completed'

        @($result.Events | Where-Object Type -eq 'StepRetrying').Count | Should -Be 1
        Should -Invoke -ModuleName IdLE.Core -CommandName Start-Sleep -Times 1 -Exactly

        (& "$script:RetryTestModuleName\Get-IdleRetryTestTransientCallCount") | Should -Be 2
    }

    It 'fails fast and does not retry when the error is not marked transient' {
        Mock -ModuleName IdLE.Core -CommandName Start-Sleep -MockWith { }

        $wfPath = Join-Path -Path $TestDrive -ChildPath 'retry-nontransient.psd1'
        Set-Content -Path $wfPath -Encoding UTF8 -Value @'
@{
  Name           = 'Retry Non-Transient Demo'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{ Name = 'NonTransientStep'; Type = 'IdLE.Step.NonTransient' }
  )
}
'@

        $req  = New-IdleLifecycleRequest -LifecycleEvent 'Joiner'

        $providers = @{
            StepRegistry = @{
                'IdLE.Step.NonTransient' = "$script:RetryTestModuleName\Invoke-IdleRetryTestNonTransientStep"
            }
            StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.NonTransient')
        }
        
        $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

        $result = Invoke-IdlePlan -Plan $plan -Providers $providers

        $result.Status | Should -Be 'Failed'
        @($result.Events | Where-Object Type -eq 'StepRetrying').Count | Should -Be 0
        Should -Invoke -ModuleName IdLE.Core -CommandName Start-Sleep -Times 0
    }
}

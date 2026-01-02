BeforeDiscovery {
    . (Join-Path $PSScriptRoot '_testHelpers.ps1')
    Import-IdleTestModule
}

BeforeAll {
    # The engine invokes step handlers by function name (string) inside module scope.
    # Therefore, test handler functions must be visible to the module (global scope).

    $script:RetryTest_CallCount_Transient = 0
    $script:RetryTest_CallCount_NonTransient = 0

    function global:Invoke-IdleRetryTestTransientStep {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [ValidateNotNull()]
            [object] $Context,

            [Parameter(Mandatory)]
            [ValidateNotNull()]
            [object] $Step
        )

        $script:RetryTest_CallCount_Transient++

        if ($script:RetryTest_CallCount_Transient -eq 1) {
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

    function global:Invoke-IdleRetryTestNonTransientStep {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [ValidateNotNull()]
            [object] $Context,

            [Parameter(Mandatory)]
            [ValidateNotNull()]
            [object] $Step
        )

        $script:RetryTest_CallCount_NonTransient++

        throw [System.Exception]::new('Non-transient failure (simulated)')
    }
}

AfterAll {
    # Cleanup global test functions to avoid polluting the session.
    Remove-Item -Path 'Function:\Invoke-IdleRetryTestTransientStep' -ErrorAction SilentlyContinue
    Remove-Item -Path 'Function:\Invoke-IdleRetryTestNonTransientStep' -ErrorAction SilentlyContinue
}

InModuleScope IdLE.Core {
    Describe 'Invoke-IdlePlan - safe retries for transient failures (fail-fast)' {

        BeforeEach {
            $script:RetryTest_CallCount_Transient = 0
            $script:RetryTest_CallCount_NonTransient = 0
        }

        It 'retries a step when the error is explicitly marked transient and then succeeds' {
            # Avoid slowing down the test run.
            Mock -CommandName Start-Sleep -MockWith { }

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
            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req

            $providers = @{
                StepRegistry = @{
                    'IdLE.Step.Transient' = 'Invoke-IdleRetryTestTransientStep'
                }
            }

            $result = Invoke-IdlePlan -Plan $plan -Providers $providers

            $result.Status | Should -Be 'Completed'
            $script:RetryTest_CallCount_Transient | Should -Be 2

            # We expect a retry event emitted by the engine retry helper.
            @($result.Events | Where-Object Type -eq 'StepRetrying').Count | Should -Be 1

            # Step result should indicate completion after retry.
            $result.Steps[0].Status | Should -Be 'Completed'

            # The engine should have attempted a delay at least once (but Start-Sleep is mocked).
            Should -Invoke -CommandName Start-Sleep -Times 1 -Exactly
        }

        It 'fails fast and does not retry when the error is not marked transient' {
            Mock -CommandName Start-Sleep -MockWith { }

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
            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req

            $providers = @{
                StepRegistry = @{
                    'IdLE.Step.NonTransient' = 'Invoke-IdleRetryTestNonTransientStep'
                }
            }

            $result = Invoke-IdlePlan -Plan $plan -Providers $providers

            $result.Status | Should -Be 'Failed'
            $script:RetryTest_CallCount_NonTransient | Should -Be 1

            # No retry events should exist for non-transient failures.
            @($result.Events | Where-Object Type -eq 'StepRetrying').Count | Should -Be 0

            # No delay should be attempted.
            Should -Invoke -CommandName Start-Sleep -Times 0
        }
    }
}

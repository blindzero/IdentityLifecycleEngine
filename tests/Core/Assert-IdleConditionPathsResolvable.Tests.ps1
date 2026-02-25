Set-StrictMode -Version Latest

BeforeDiscovery {
    . (Join-Path (Split-Path -Path $PSScriptRoot -Parent) '_testHelpers.ps1')
    Import-IdleTestModule
}

Describe 'Assert-IdleConditionPathsResolvable' {
    InModuleScope 'IdLE.Core' {
        It 'accepts condition paths that exist in planning context' {
            $condition = @{
                All = @(
                    @{ Equals = @{ Path = 'Plan.LifecycleEvent'; Value = 'Joiner' } }
                    @{ Exists = 'Request.Intent.OffboardingDate' }
                )
            }

            $context = @{
                Plan    = @{ LifecycleEvent = 'Joiner' }
                Request = @{ Intent = @{ OffboardingDate = '2026-02-30' }; Context = @{}; IdentityKeys = @{} }
            }

            {
                Assert-IdleConditionPathsResolvable -Condition $condition -Context $context -StepName 'CheckPaths' -Source 'Condition'
            } | Should -Not -Throw
        }

        It 'throws when at least one condition path does not exist in planning context' {
            $condition = @{
                All = @(
                    @{ Equals = @{ Path = 'Plan.LifecycleEvent'; Value = 'Joiner' } }
                    @{ Exists = 'Request.Context.OffboardingDate' }
                )
            }

            $context = @{
                Plan    = @{ LifecycleEvent = 'Joiner' }
                Request = @{ Intent = @{ OffboardingDate = '2026-02-30' }; Context = @{}; IdentityKeys = @{} }
            }

            {
                Assert-IdleConditionPathsResolvable -Condition $condition -Context $context -StepName 'CheckPaths' -Source 'Condition'
            } | Should -Throw
        }

        It 'reports unresolved paths in one clear error message with step/source context' {
            $condition = @{
                All = @(
                    @{ Exists = 'Request.Context.OffboardingDate' }
                    @{ Exists = 'Request.Context.Manager' }
                )
            }

            $context = @{
                Plan    = @{ LifecycleEvent = 'Joiner' }
                Request = @{ Intent = @{ OffboardingDate = '2026-02-30' }; Context = @{}; IdentityKeys = @{} }
            }

            {
                Assert-IdleConditionPathsResolvable -Condition $condition -Context $context -StepName 'RegionCheck' -Source 'Precondition'
            } | Should -Throw "*Workflow step 'RegionCheck' has unresolved condition path(s) in Precondition:*Request.Context.OffboardingDate*Request.Context.Manager*"
        }
    }
}

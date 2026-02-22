Set-StrictMode -Version Latest

BeforeAll {
    . (Join-Path (Split-Path -Path $PSScriptRoot -Parent) '_testHelpers.ps1')
    Import-IdleTestModule

    $script:FixturesPath = Join-Path $PSScriptRoot '..' 'fixtures/workflows'

    function global:Invoke-IdleContextResolverTestNoopStep {
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
}

AfterAll {
    Remove-Item -Path 'Function:\Invoke-IdleContextResolverTestNoopStep' -ErrorAction SilentlyContinue
}

Describe 'New-IdlePlan - ContextResolvers' {

    Context 'Resolver runs before conditions and influences step applicability' {
        It 'resolver populates Request.Context and condition references resolved data' {
            $wfPath = Join-Path $script:FixturesPath 'resolver-condition.psd1'

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner' -IdentityKeys @{ Id = 'user1' }

            $provider = New-IdleMockIdentityProvider -InitialStore @{
                'user1' = @{
                    IdentityKey  = 'user1'
                    Enabled      = $true
                    Attributes   = @{}
                    Entitlements = @(
                        @{ Kind = 'Group'; Id = 'g1' }
                    )
                }
            }

            $providers = @{
                Identity     = $provider
                StepRegistry = @{ 'IdLE.Step.EmitEvent' = 'Invoke-IdleContextResolverTestNoopStep' }
            }

            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

            $plan | Should -Not -BeNullOrEmpty
            $plan.Steps[0].Status | Should -Be 'Planned'

            # Snapshot captures resolved context (predefined path: Identity.Entitlements)
            $plan.Request.Context | Should -Not -BeNullOrEmpty
            $plan.Request.Context.Identity | Should -Not -BeNullOrEmpty
            $entitlements = @($plan.Request.Context.Identity.Entitlements)
            $entitlements.Count | Should -Be 1
            $entitlements[0].Id | Should -Be 'g1'
        }

        It 'step is NotApplicable when resolver returns empty entitlements and condition requires them' {
            $wfPath = Join-Path $script:FixturesPath 'resolver-empty-entitlements.psd1'

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner' -IdentityKeys @{ Id = 'user2' }

            $provider = New-IdleMockIdentityProvider -InitialStore @{
                'user2' = @{
                    IdentityKey  = 'user2'
                    Enabled      = $true
                    Attributes   = @{}
                    Entitlements = @()
                }
            }

            $providers = @{
                Identity     = $provider
                StepRegistry = @{ 'IdLE.Step.EmitEvent' = 'Invoke-IdleContextResolverTestNoopStep' }
            }

            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

            # Resolver ran but returned an empty list.
            # PowerShell collapses empty arrays to $null in pipeline output, so Get-IdleValueByPath
            # returns $null for the path, and the Exists condition evaluates to $false.
            $plan | Should -Not -BeNullOrEmpty
            $plan.Steps[0].Status | Should -Be 'NotApplicable'
        }

        It 'IdLE.Identity.Read resolver populates Request.Context.Identity.Profile' {
            $wfPath = Join-Path $script:FixturesPath 'resolver-identity-read.psd1'

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner' -IdentityKeys @{ Id = 'user1' }

            $provider = New-IdleMockIdentityProvider -InitialStore @{
                'user1' = @{
                    IdentityKey  = 'user1'
                    Enabled      = $true
                    Attributes   = @{ Department = 'IT' }
                    Entitlements = @()
                }
            }

            $providers = @{
                Identity     = $provider
                StepRegistry = @{ 'IdLE.Step.EmitEvent' = 'Invoke-IdleContextResolverTestNoopStep' }
            }

            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

            $plan | Should -Not -BeNullOrEmpty
            # Predefined path for IdLE.Identity.Read is Identity.Profile
            $plan.Steps[0].Status | Should -Be 'Planned'
            $plan.Request.Context.Identity.Profile | Should -Not -BeNullOrEmpty
            $plan.Request.Context.Identity.Profile.IdentityKey | Should -Be 'user1'
        }
    }

    Context 'To is not a supported key (output path is predefined per capability)' {
        It 'rejects a resolver entry that specifies To (unknown key)' {
            $wfPath = Join-Path $script:FixturesPath 'resolver-with-to-key.psd1'

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner'

            { New-IdlePlan -WorkflowPath $wfPath -Request $req } |
                Should -Throw -ExpectedMessage "*Unknown key*To*"
        }
    }

    Context 'Non-allow-listed capability' {
        It 'rejects a resolver that uses a capability not in the read-only allow-list' {
            $wfPath = Join-Path $script:FixturesPath 'resolver-non-allowlisted-cap.psd1'

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner'

            { New-IdlePlan -WorkflowPath $wfPath -Request $req } |
                Should -Throw -ExpectedMessage "*not in the read-only allow-list*"
        }
    }

    Context 'Resolver output captured in plan snapshot' {
        It 'plan.Request.Context contains the resolved value after planning' {
            $wfPath = Join-Path $script:FixturesPath 'resolver-snapshot.psd1'

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner'

            $provider = New-IdleMockIdentityProvider -InitialStore @{
                'snap-user' = @{
                    IdentityKey  = 'snap-user'
                    Enabled      = $true
                    Attributes   = @{}
                    Entitlements = @(
                        @{ Kind = 'Role'; Id = 'admin' }
                    )
                }
            }

            $providers = @{
                Identity     = $provider
                StepRegistry = @{ 'IdLE.Step.EmitEvent' = 'Invoke-IdleContextResolverTestNoopStep' }
            }

            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

            $plan.Request | Should -Not -BeNullOrEmpty
            $plan.Request.Context | Should -Not -BeNullOrEmpty
            # IdLE.Entitlement.List always writes to predefined path: Identity.Entitlements
            $snap = @($plan.Request.Context.Identity.Entitlements)
            $snap.Count | Should -Be 1
            $snap[0].Kind | Should -Be 'Role'
            $snap[0].Id | Should -Be 'admin'
        }
    }

    Context 'Provider auto-selection' {
        It 'auto-selects provider when Provider is not specified in resolver' {
            $wfPath = Join-Path $script:FixturesPath 'resolver-autoselect.psd1'

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner'

            $provider = New-IdleMockIdentityProvider -InitialStore @{
                'auto-user' = @{
                    IdentityKey  = 'auto-user'
                    Enabled      = $true
                    Attributes   = @{}
                    Entitlements = @(
                        @{ Kind = 'Group'; Id = 'grp-auto' }
                    )
                }
            }

            # Provider is registered without an explicit alias in the resolver
            $providers = @{
                IdentityProvider = $provider
                StepRegistry     = @{ 'IdLE.Step.EmitEvent' = 'Invoke-IdleContextResolverTestNoopStep' }
            }

            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

            $plan | Should -Not -BeNullOrEmpty
            $entitlements = @($plan.Request.Context.Identity.Entitlements)
            $entitlements.Count | Should -Be 1
            $entitlements[0].Id | Should -Be 'grp-auto'
        }

        It 'fails when no provider supports the capability and Provider is not specified' {
            $wfPath = Join-Path $script:FixturesPath 'resolver-no-provider.psd1'

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner'

            # No provider supports IdLE.Entitlement.List
            $dummyProvider = [pscustomobject]@{}
            $dummyProvider | Add-Member -MemberType ScriptMethod -Name GetCapabilities -Value { return @() }

            $providers = @{
                Dummy        = $dummyProvider
                StepRegistry = @{ 'IdLE.Step.EmitEvent' = 'Invoke-IdleContextResolverTestNoopStep' }
            }

            { New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers } |
                Should -Throw -ExpectedMessage "*no provider*Providers map*"
        }
    }

    Context 'Workflow schema validation for ContextResolvers' {
        It 'rejects unknown keys in a resolver entry' {
            $wfPath = Join-Path $script:FixturesPath 'resolver-unknown-key.psd1'

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner'

            { New-IdlePlan -WorkflowPath $wfPath -Request $req } |
                Should -Throw -ExpectedMessage "*Unknown key*UnknownKey*"
        }

        It 'rejects a resolver missing the required Capability key' {
            $wfPath = Join-Path $script:FixturesPath 'resolver-missing-capability.psd1'

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner'

            { New-IdlePlan -WorkflowPath $wfPath -Request $req } |
                Should -Throw -ExpectedMessage "*Capability*"
        }
    }

    Context 'Template resolution in With' {
        It 'resolves Request.IdentityKeys template in With.IdentityKey' {
            $wfPath = Join-Path $script:FixturesPath 'resolver-template.psd1'

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner' -IdentityKeys @{ Id = 'tmpl-user' }

            $provider = New-IdleMockIdentityProvider -InitialStore @{
                'tmpl-user' = @{
                    IdentityKey  = 'tmpl-user'
                    Enabled      = $true
                    Attributes   = @{}
                    Entitlements = @(
                        @{ Kind = 'Group'; Id = 'tmpl-grp' }
                    )
                }
            }

            $providers = @{
                Identity     = $provider
                StepRegistry = @{ 'IdLE.Step.EmitEvent' = 'Invoke-IdleContextResolverTestNoopStep' }
            }

            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

            $entitlements = @($plan.Request.Context.Identity.Entitlements)
            $entitlements.Count | Should -Be 1
            $entitlements[0].Id | Should -Be 'tmpl-grp'
        }
    }
}

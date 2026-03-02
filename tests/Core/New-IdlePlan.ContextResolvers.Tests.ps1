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

        It 'IdLE.Identity.Read resolver flattens Attributes to top-level properties' {
            $wfPath = Join-Path $script:FixturesPath 'resolver-identity-read.psd1'

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner' -IdentityKeys @{ Id = 'user1' }

            $provider = New-IdleMockIdentityProvider -InitialStore @{
                'user1' = @{
                    IdentityKey  = 'user1'
                    Enabled      = $true
                    Attributes   = @{
                        DisplayName        = 'User One'
                        Department         = 'IT'
                        EmailAddress       = 'user1@example.com'
                        UserPrincipalName  = 'user1@example.com'
                    }
                    Entitlements = @()
                }
            }

            $providers = @{
                Identity     = $provider
                StepRegistry = @{ 'IdLE.Step.EmitEvent' = 'Invoke-IdleContextResolverTestNoopStep' }
            }

            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

            $plan | Should -Not -BeNullOrEmpty
            $profile = $plan.Request.Context.Identity.Profile

            # Core properties should be present
            $profile.IdentityKey | Should -Be 'user1'
            $profile.Enabled | Should -Be $true

            # Attributes hashtable should be preserved for backwards compatibility
            $profile.Attributes | Should -Not -BeNullOrEmpty
            $profile.Attributes | Should -BeOfType [hashtable]
            $profile.Attributes.DisplayName | Should -Be 'User One'

            # Attributes should be flattened to top level for direct access
            $profile.DisplayName | Should -Be 'User One'
            $profile.Department | Should -Be 'IT'
            $profile.EmailAddress | Should -Be 'user1@example.com'
            $profile.UserPrincipalName | Should -Be 'user1@example.com'
            
            # PSTypeName should be preserved from the original identity object
            $profile.PSObject.TypeNames | Should -Contain 'IdLE.Identity'
        }

        It 'IdLE.Identity.Read resolver handles null Attributes gracefully' {
            $wfPath = Join-Path $script:FixturesPath 'resolver-identity-read.psd1'

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner' -IdentityKeys @{ Id = 'user1' }

            $provider = New-IdleMockIdentityProvider -InitialStore @{
                'user1' = @{
                    IdentityKey  = 'user1'
                    Enabled      = $true
                    Attributes   = $null
                    Entitlements = @()
                }
            }

            $providers = @{
                Identity     = $provider
                StepRegistry = @{ 'IdLE.Step.EmitEvent' = 'Invoke-IdleContextResolverTestNoopStep' }
            }

            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

            $plan | Should -Not -BeNullOrEmpty
            $profile = $plan.Request.Context.Identity.Profile

            # Core properties should be present
            $profile.IdentityKey | Should -Be 'user1'
            $profile.Enabled | Should -Be $true

            # Attributes should be null (not an empty hashtable)
            $profile.PSObject.Properties.Name | Should -Contain 'Attributes'
            $profile.Attributes | Should -Be $null
        }

        It 'IdLE.Identity.Read resolver handles empty Attributes hashtable' {
            $wfPath = Join-Path $script:FixturesPath 'resolver-identity-read.psd1'

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner' -IdentityKeys @{ Id = 'user1' }

            $provider = New-IdleMockIdentityProvider -InitialStore @{
                'user1' = @{
                    IdentityKey  = 'user1'
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

            $plan | Should -Not -BeNullOrEmpty
            $profile = $plan.Request.Context.Identity.Profile

            # Core properties should be present
            $profile.IdentityKey | Should -Be 'user1'
            $profile.Enabled | Should -Be $true

            # Attributes should be an empty hashtable (not null)
            $profile.Attributes | Should -BeOfType [hashtable]
            $profile.Attributes.Count | Should -Be 0
        }

        It 'IdLE.Identity.Read resolver does not overwrite core properties with conflicting attributes' {
            $wfPath = Join-Path $script:FixturesPath 'resolver-identity-read.psd1'

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner' -IdentityKeys @{ Id = 'user1' }

            $provider = New-IdleMockIdentityProvider -InitialStore @{
                'user1' = @{
                    IdentityKey  = 'user1'
                    Enabled      = $true
                    Attributes   = @{
                        IdentityKey = 'conflicting-value'  # This conflicts with core property
                        Enabled     = $false                # This also conflicts
                        DisplayName = 'User One'
                    }
                    Entitlements = @()
                }
            }

            $providers = @{
                Identity     = $provider
                StepRegistry = @{ 'IdLE.Step.EmitEvent' = 'Invoke-IdleContextResolverTestNoopStep' }
            }

            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

            $plan | Should -Not -BeNullOrEmpty
            $profile = $plan.Request.Context.Identity.Profile

            # Core IdentityKey should NOT be overwritten by conflicting attribute
            $profile.IdentityKey | Should -Be 'user1'

            # Core Enabled should NOT be overwritten by conflicting attribute
            $profile.Enabled | Should -Be $true

            # DisplayName should be flattened (no conflict)
            $profile.DisplayName | Should -Be 'User One'

            # Conflicting attributes should still be accessible via Attributes hashtable
            $profile.Attributes.IdentityKey | Should -Be 'conflicting-value'
            $profile.Attributes.Enabled | Should -Be $false
            $profile.Attributes.DisplayName | Should -Be 'User One'
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

        It 'resolves templates using flattened Identity.Profile attributes' {
            # Create a workflow with a step that uses template substitution with Identity.Profile attributes
            $wfContent = @'
@{
    Name = 'Identity Profile Template Test'
    LifecycleEvent = 'Joiner'
    ContextResolvers = @(
        @{
            Capability = 'IdLE.Identity.Read'
            With = @{
                IdentityKey = '{{Request.IdentityKeys.Id}}'
                Provider = 'Identity'
            }
        }
    )
    Steps = @(
        @{
            Name = 'TestStep'
            Type = 'IdLE.Step.EmitEvent'
            With = @{
                Message = 'User: {{Request.Context.Identity.Profile.DisplayName}}, Email: {{Request.Context.Identity.Profile.EmailAddress}}'
                Department = '{{Request.Context.Identity.Profile.Department}}'
            }
        }
    )
}
'@
            $tempWfPath = Join-Path $TestDrive 'wf-identity-profile-template.psd1'
            Set-Content -Path $tempWfPath -Value $wfContent

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner' -IdentityKeys @{ Id = 'user1' }

            $provider = New-IdleMockIdentityProvider -InitialStore @{
                'user1' = @{
                    IdentityKey  = 'user1'
                    Enabled      = $true
                    Attributes   = @{
                        DisplayName   = 'John Doe'
                        EmailAddress  = 'john.doe@example.com'
                        Department    = 'Engineering'
                    }
                    Entitlements = @()
                }
            }

            $providers = @{
                Identity     = $provider
                StepRegistry = @{ 'IdLE.Step.EmitEvent' = 'Invoke-IdleContextResolverTestNoopStep' }
            }

            $plan = New-IdlePlan -WorkflowPath $tempWfPath -Request $req -Providers $providers

            $plan | Should -Not -BeNullOrEmpty
            $plan.Steps[0].Status | Should -Be 'Planned'
            # Verify templates were resolved using flattened attributes
            $plan.Steps[0].With.Message | Should -Be 'User: John Doe, Email: john.doe@example.com'
            $plan.Steps[0].With.Department | Should -Be 'Engineering'
        }
    }

    Context 'Auth session threading' {
        It 'passes AuthSession to ListEntitlements when provider method supports it' {
            $wfPath = Join-Path $script:FixturesPath 'resolver-with-auth-session.psd1'

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner'

            # Provider that captures the auth session passed to ListEntitlements
            $provider = [pscustomobject]@{ CapturedSession = $null }
            $provider | Add-Member -MemberType ScriptMethod -Name GetCapabilities -Value {
                return @('IdLE.Entitlement.List')
            }
            $provider | Add-Member -MemberType ScriptMethod -Name ListEntitlements -Value {
                param([string]$IdentityKey, [object]$AuthSession)
                $this.CapturedSession = $AuthSession
                return @(@{ Kind = 'Group'; Id = 'auth-grp' })
            }

            $broker = New-IdleAuthSessionBroker -AuthSessionType 'OAuth' -DefaultAuthSession 'test-token'

            $providers = @{
                Identity          = $provider
                AuthSessionBroker = $broker
                StepRegistry      = @{ 'IdLE.Step.EmitEvent' = 'Invoke-IdleContextResolverTestNoopStep' }
            }

            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

            $plan | Should -Not -BeNullOrEmpty
            # Auth session was passed through to the provider
            $provider.CapturedSession | Should -Not -BeNullOrEmpty
            $entitlements = @($plan.Request.Context.Identity.Entitlements)
            $entitlements.Count | Should -Be 1
            $entitlements[0].Id | Should -Be 'auth-grp'
        }
    }

    Context 'Provider ambiguity detection' {
        It 'fails when multiple providers support the same capability and Provider is not specified' {
            $wfPath = Join-Path $script:FixturesPath 'resolver-ambiguous-provider.psd1'

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner'

            $makeProvider = {
                $p = [pscustomobject]@{}
                $p | Add-Member -MemberType ScriptMethod -Name GetCapabilities -Value { return @('IdLE.Entitlement.List') }
                $p | Add-Member -MemberType ScriptMethod -Name ListEntitlements -Value { param([string]$IdentityKey) return @() }
                return $p
            }

            $providers = @{
                Provider1    = & $makeProvider
                Provider2    = & $makeProvider
                StepRegistry = @{ 'IdLE.Step.EmitEvent' = 'Invoke-IdleContextResolverTestNoopStep' }
            }

            { New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers } |
                Should -Throw -ExpectedMessage "*Multiple providers*disambiguate*"
        }
    }

    Context 'Context type conflict detection' {
        It 'fails when an intermediate context node is a non-dictionary type' {
            $wfPath = Join-Path $script:FixturesPath 'resolver-context-type-conflict.psd1'

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner' -Context @{
                # Pre-populate Identity as a scalar string, conflicting with the predefined path
                Identity = 'some-scalar-value'
            }

            $provider = New-IdleMockIdentityProvider -InitialStore @{
                'user1' = @{
                    IdentityKey  = 'user1'
                    Enabled      = $true
                    Attributes   = @{}
                    Entitlements = @(@{ Kind = 'Group'; Id = 'g1' })
                }
            }

            $providers = @{
                Identity     = $provider
                StepRegistry = @{ 'IdLE.Step.EmitEvent' = 'Invoke-IdleContextResolverTestNoopStep' }
            }

            { New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers } |
                Should -Throw -ExpectedMessage "*intermediate node*Identity*"
        }
    }

    Context 'Request.Context guard in New-IdlePlanObject' {
        It 'creates Request.Context when the request has no Context property' {
            $wfPath = Join-Path $script:FixturesPath 'resolver-condition.psd1'

            # Create a minimal request object without Context
            $req = [pscustomobject]@{
                LifecycleEvent = 'Joiner'
                CorrelationId  = [System.Guid]::NewGuid().ToString()
                IdentityKeys   = @{ Id = 'user1' }
            }

            $provider = New-IdleMockIdentityProvider -InitialStore @{
                'user1' = @{
                    IdentityKey  = 'user1'
                    Enabled      = $true
                    Attributes   = @{}
                    Entitlements = @(@{ Kind = 'Group'; Id = 'g1' })
                }
            }

            $providers = @{
                Identity     = $provider
                StepRegistry = @{ 'IdLE.Step.EmitEvent' = 'Invoke-IdleContextResolverTestNoopStep' }
            }

            # Should not throw even though request has no Context property
            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

            $plan | Should -Not -BeNullOrEmpty
            $plan.Request.Context | Should -Not -BeNullOrEmpty
        }
    }
}

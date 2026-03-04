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

            # Results written to scoped path: Providers.<ProviderAlias>.Default.<CapabilitySubPath>
            $plan.Request.Context | Should -Not -BeNullOrEmpty
            $plan.Request.Context.Providers | Should -Not -BeNullOrEmpty
            $scopedEntitlements = @($plan.Request.Context.Providers.Identity.Default.Identity.Entitlements)
            $scopedEntitlements.Count | Should -Be 1
            $scopedEntitlements[0].Id | Should -Be 'g1'

            # Global view is also populated: Views.<CapabilitySubPath>
            $viewEntitlements = @($plan.Request.Context.Views.Identity.Entitlements)
            $viewEntitlements.Count | Should -Be 1
            $viewEntitlements[0].Id | Should -Be 'g1'
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

        It 'IdLE.Identity.Read resolver populates scoped path Providers.Identity.Default.Identity.Profile' {
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
            # Scoped path for IdLE.Identity.Read: Providers.<Provider>.Default.Identity.Profile
            $plan.Steps[0].Status | Should -Be 'Planned'
            $plan.Request.Context.Providers.Identity.Default.Identity.Profile | Should -Not -BeNullOrEmpty
            $plan.Request.Context.Providers.Identity.Default.Identity.Profile.IdentityKey | Should -Be 'user1'
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
        It 'plan.Request.Context contains the resolved value after planning (scoped path and view)' {
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

            # Scoped path: Providers.<Provider>.Default.Identity.Entitlements
            $scoped = @($plan.Request.Context.Providers.Identity.Default.Identity.Entitlements)
            $scoped.Count | Should -Be 1
            $scoped[0].Kind | Should -Be 'Role'
            $scoped[0].Id | Should -Be 'admin'

            # Global view: Views.Identity.Entitlements
            $view = @($plan.Request.Context.Views.Identity.Entitlements)
            $view.Count | Should -Be 1
            $view[0].Kind | Should -Be 'Role'
            $view[0].Id | Should -Be 'admin'
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
            # Auto-selected provider alias is 'IdentityProvider'
            $entitlements = @($plan.Request.Context.Providers.IdentityProvider.Default.Identity.Entitlements)
            $entitlements.Count | Should -Be 1
            $entitlements[0].Id | Should -Be 'grp-auto'

            # Global view is also populated
            $viewEntitlements = @($plan.Request.Context.Views.Identity.Entitlements)
            $viewEntitlements.Count | Should -Be 1
            $viewEntitlements[0].Id | Should -Be 'grp-auto'
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

            $entitlements = @($plan.Request.Context.Providers.Identity.Default.Identity.Entitlements)
            $entitlements.Count | Should -Be 1
            $entitlements[0].Id | Should -Be 'tmpl-grp'
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

            # Results written to scoped path using the AuthSessionName as key: Providers.Identity.TestSession.Identity.Entitlements
            $entitlements = @($plan.Request.Context.Providers.Identity.TestSession.Identity.Entitlements)
            $entitlements.Count | Should -Be 1
            $entitlements[0].Id | Should -Be 'auth-grp'

            # Global view also populated
            $viewEntitlements = @($plan.Request.Context.Views.Identity.Entitlements)
            $viewEntitlements.Count | Should -Be 1
            $viewEntitlements[0].Id | Should -Be 'auth-grp'
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
                # Pre-populate Providers as a scalar string, conflicting with the new scoped path
                Providers = 'some-scalar-value'
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
                Should -Throw -ExpectedMessage "*intermediate node*Providers*"
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

    Context 'Provider/Auth-scoped namespace (source of truth)' {
        It 'two providers writing the same capability produce independent scoped paths without collision' {
            $wfPath = Join-Path $script:FixturesPath 'resolver-two-providers.psd1'

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner'

            $makeProvider = {
                param([string]$GroupId)
                # Store GroupId on the object so the ScriptMethod can access it via $this
                $p = [pscustomobject]@{ FixtureGroupId = $GroupId }
                $p | Add-Member -MemberType ScriptMethod -Name GetCapabilities -Value { return @('IdLE.Entitlement.List') }
                $p | Add-Member -MemberType ScriptMethod -Name ListEntitlements -Value {
                    param([string]$IdentityKey)
                    return @(@{ Kind = 'Group'; Id = $this.FixtureGroupId })
                }
                return $p
            }

            $providers = @{
                Entra        = & $makeProvider -GroupId 'entra-grp'
                AD           = & $makeProvider -GroupId 'ad-grp'
                StepRegistry = @{ 'IdLE.Step.EmitEvent' = 'Invoke-IdleContextResolverTestNoopStep' }
            }

            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

            $plan | Should -Not -BeNullOrEmpty

            # Each provider writes to its own scoped path without overwriting the other
            $entraEntitlements = @($plan.Request.Context.Providers.Entra.Default.Identity.Entitlements)
            $entraEntitlements.Count | Should -Be 1
            $entraEntitlements[0].Id | Should -Be 'entra-grp'

            $adEntitlements = @($plan.Request.Context.Providers.AD.Default.Identity.Entitlements)
            $adEntitlements.Count | Should -Be 1
            $adEntitlements[0].Id | Should -Be 'ad-grp'
        }

        It 'multiple auth sessions for same provider produce independent scoped paths' {
            $wfPath = Join-Path $script:FixturesPath 'resolver-two-auth-sessions.psd1'

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner'

            $provider = [pscustomobject]@{}
            $provider | Add-Member -MemberType ScriptMethod -Name GetCapabilities -Value { return @('IdLE.Entitlement.List') }
            $provider | Add-Member -MemberType ScriptMethod -Name ListEntitlements -Value {
                param([string]$IdentityKey, [object]$AuthSession)
                return @(@{ Kind = 'Group'; Id = "grp-from-$AuthSession" })
            }

            $broker = New-IdleAuthSessionBroker -AuthSessionType 'OAuth' -DefaultAuthSession 'token-corp'
            $broker | Add-Member -MemberType ScriptMethod -Name AcquireAuthSession -Value {
                param([string]$Name, $Options)
                if ($Name -eq 'Corp') { return 'token-corp' }
                if ($Name -eq 'Tier0') { return 'token-tier0' }
                return 'token-default'
            } -Force

            $providers = @{
                Identity          = $provider
                AuthSessionBroker = $broker
                StepRegistry      = @{ 'IdLE.Step.EmitEvent' = 'Invoke-IdleContextResolverTestNoopStep' }
            }

            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

            $plan | Should -Not -BeNullOrEmpty

            # Each auth session writes to its own scoped path
            $corpEntitlements = @($plan.Request.Context.Providers.Identity.Corp.Identity.Entitlements)
            $corpEntitlements.Count | Should -Be 1
            $corpEntitlements[0].Id | Should -Be 'grp-from-token-corp'

            $tier0Entitlements = @($plan.Request.Context.Providers.Identity.Tier0.Identity.Entitlements)
            $tier0Entitlements.Count | Should -Be 1
            $tier0Entitlements[0].Id | Should -Be 'grp-from-token-tier0'
        }
    }

    Context 'Deterministic Views for IdLE.Entitlement.List' {
        It 'global view merges entitlements from all providers sorted by provider alias then auth session key' {
            $wfPath = Join-Path $script:FixturesPath 'resolver-two-providers.psd1'

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner'

            $makeProvider = {
                param([string]$GroupId)
                $p = [pscustomobject]@{ FixtureGroupId = $GroupId }
                $p | Add-Member -MemberType ScriptMethod -Name GetCapabilities -Value { return @('IdLE.Entitlement.List') }
                $p | Add-Member -MemberType ScriptMethod -Name ListEntitlements -Value {
                    param([string]$IdentityKey)
                    return @(@{ Kind = 'Group'; Id = $this.FixtureGroupId })
                }
                return $p
            }

            $providers = @{
                Entra        = & $makeProvider -GroupId 'entra-grp'
                AD           = & $makeProvider -GroupId 'ad-grp'
                StepRegistry = @{ 'IdLE.Step.EmitEvent' = 'Invoke-IdleContextResolverTestNoopStep' }
            }

            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

            # Global view contains both providers' entitlements (sorted: AD before Entra alphabetically)
            $globalView = @($plan.Request.Context.Views.Identity.Entitlements)
            $globalView.Count | Should -Be 2
            $ids = $globalView | ForEach-Object { $_.Id }
            $ids | Should -Contain 'entra-grp'
            $ids | Should -Contain 'ad-grp'
        }

        It 'provider view contains only entitlements for that provider' {
            $wfPath = Join-Path $script:FixturesPath 'resolver-two-providers.psd1'

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner'

            $makeProvider = {
                param([string]$GroupId)
                $p = [pscustomobject]@{ FixtureGroupId = $GroupId }
                $p | Add-Member -MemberType ScriptMethod -Name GetCapabilities -Value { return @('IdLE.Entitlement.List') }
                $p | Add-Member -MemberType ScriptMethod -Name ListEntitlements -Value {
                    param([string]$IdentityKey)
                    return @(@{ Kind = 'Group'; Id = $this.FixtureGroupId })
                }
                return $p
            }

            $providers = @{
                Entra        = & $makeProvider -GroupId 'entra-grp'
                AD           = & $makeProvider -GroupId 'ad-grp'
                StepRegistry = @{ 'IdLE.Step.EmitEvent' = 'Invoke-IdleContextResolverTestNoopStep' }
            }

            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

            # Provider view for Entra contains only Entra entitlements
            $entraView = @($plan.Request.Context.Views.Providers.Entra.Identity.Entitlements)
            $entraView.Count | Should -Be 1
            $entraView[0].Id | Should -Be 'entra-grp'

            # Provider view for AD contains only AD entitlements
            $adView = @($plan.Request.Context.Views.Providers.AD.Identity.Entitlements)
            $adView.Count | Should -Be 1
            $adView[0].Id | Should -Be 'ad-grp'
        }

        It 'entitlement entries include SourceProvider and SourceAuthSessionName metadata' {
            $wfPath = Join-Path $script:FixturesPath 'resolver-with-auth-session.psd1'

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner'

            $provider = [pscustomobject]@{}
            $provider | Add-Member -MemberType ScriptMethod -Name GetCapabilities -Value { return @('IdLE.Entitlement.List') }
            $provider | Add-Member -MemberType ScriptMethod -Name ListEntitlements -Value {
                param([string]$IdentityKey, [object]$AuthSession)
                return @(@{ Kind = 'Group'; Id = 'src-grp' })
            }

            $broker = New-IdleAuthSessionBroker -AuthSessionType 'OAuth' -DefaultAuthSession 'test-token'

            $providers = @{
                Identity          = $provider
                AuthSessionBroker = $broker
                StepRegistry      = @{ 'IdLE.Step.EmitEvent' = 'Invoke-IdleContextResolverTestNoopStep' }
            }

            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

            $entitlements = @($plan.Request.Context.Providers.Identity.TestSession.Identity.Entitlements)
            $entitlements.Count | Should -Be 1
            $entitlements[0].SourceProvider | Should -Be 'Identity'
            $entitlements[0].SourceAuthSessionName | Should -Be 'TestSession'
        }

        It 'entitlement entries without explicit auth session have SourceAuthSessionName Default' {
            $wfPath = Join-Path $script:FixturesPath 'resolver-snapshot.psd1'

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner'

            $provider = New-IdleMockIdentityProvider -InitialStore @{
                'snap-user' = @{
                    IdentityKey  = 'snap-user'
                    Enabled      = $true
                    Attributes   = @{}
                    Entitlements = @(@{ Kind = 'Role'; Id = 'admin' })
                }
            }

            $providers = @{
                Identity     = $provider
                StepRegistry = @{ 'IdLE.Step.EmitEvent' = 'Invoke-IdleContextResolverTestNoopStep' }
            }

            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

            $entitlements = @($plan.Request.Context.Providers.Identity.Default.Identity.Entitlements)
            $entitlements.Count | Should -Be 1
            $entitlements[0].SourceProvider | Should -Be 'Identity'
            $entitlements[0].SourceAuthSessionName | Should -Be 'Default'
        }

        It 'session view (all providers, one auth session) contains entitlements from all providers using that session key' {
            $wfPath = Join-Path $script:FixturesPath 'resolver-two-auth-sessions.psd1'

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner'

            $provider = [pscustomobject]@{}
            $provider | Add-Member -MemberType ScriptMethod -Name GetCapabilities -Value { return @('IdLE.Entitlement.List') }
            $provider | Add-Member -MemberType ScriptMethod -Name ListEntitlements -Value {
                param([string]$IdentityKey, [object]$AuthSession)
                return @(@{ Kind = 'Group'; Id = "grp-from-$AuthSession" })
            }

            $broker = New-IdleAuthSessionBroker -AuthSessionType 'OAuth' -DefaultAuthSession 'token-corp'
            $broker | Add-Member -MemberType ScriptMethod -Name AcquireAuthSession -Value {
                param([string]$Name, $Options)
                if ($Name -eq 'Corp') { return 'token-corp' }
                if ($Name -eq 'Tier0') { return 'token-tier0' }
                return 'token-default'
            } -Force

            $providers = @{
                Identity          = $provider
                AuthSessionBroker = $broker
                StepRegistry      = @{ 'IdLE.Step.EmitEvent' = 'Invoke-IdleContextResolverTestNoopStep' }
            }

            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

            # Session view for Corp: all providers that ran with the Corp session
            $corpView = @($plan.Request.Context.Views.Sessions.Corp.Identity.Entitlements)
            $corpView.Count | Should -Be 1
            $corpView[0].Id | Should -Be 'grp-from-token-corp'

            # Session view for Tier0: all providers that ran with the Tier0 session
            $tier0View = @($plan.Request.Context.Views.Sessions.Tier0.Identity.Entitlements)
            $tier0View.Count | Should -Be 1
            $tier0View[0].Id | Should -Be 'grp-from-token-tier0'
        }

        It 'provider+session view (one provider, one auth session) contains only that exact combination' {
            $wfPath = Join-Path $script:FixturesPath 'resolver-two-auth-sessions.psd1'

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner'

            $provider = [pscustomobject]@{}
            $provider | Add-Member -MemberType ScriptMethod -Name GetCapabilities -Value { return @('IdLE.Entitlement.List') }
            $provider | Add-Member -MemberType ScriptMethod -Name ListEntitlements -Value {
                param([string]$IdentityKey, [object]$AuthSession)
                return @(@{ Kind = 'Group'; Id = "grp-from-$AuthSession" })
            }

            $broker = New-IdleAuthSessionBroker -AuthSessionType 'OAuth' -DefaultAuthSession 'token-corp'
            $broker | Add-Member -MemberType ScriptMethod -Name AcquireAuthSession -Value {
                param([string]$Name, $Options)
                if ($Name -eq 'Corp') { return 'token-corp' }
                if ($Name -eq 'Tier0') { return 'token-tier0' }
                return 'token-default'
            } -Force

            $providers = @{
                Identity          = $provider
                AuthSessionBroker = $broker
                StepRegistry      = @{ 'IdLE.Step.EmitEvent' = 'Invoke-IdleContextResolverTestNoopStep' }
            }

            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

            # Provider+Session view: Identity provider + Corp session only
            $identityCorpView = @($plan.Request.Context.Views.Providers.Identity.Sessions.Corp.Identity.Entitlements)
            $identityCorpView.Count | Should -Be 1
            $identityCorpView[0].Id | Should -Be 'grp-from-token-corp'

            # Provider+Session view: Identity provider + Tier0 session only
            $identityTier0View = @($plan.Request.Context.Views.Providers.Identity.Sessions.Tier0.Identity.Entitlements)
            $identityTier0View.Count | Should -Be 1
            $identityTier0View[0].Id | Should -Be 'grp-from-token-tier0'
        }
    }

    Context 'Deterministic Views for IdLE.Identity.Read' {
        It 'profile includes SourceProvider and SourceAuthSessionName metadata' {
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

            $profile = $plan.Request.Context.Providers.Identity.Default.Identity.Profile
            $profile.SourceProvider | Should -Be 'Identity'
            $profile.SourceAuthSessionName | Should -Be 'Default'
        }

        It 'global view (all providers, all sessions) contains the last profile in sort order' {
            $wfPath = Join-Path $script:FixturesPath 'resolver-identity-read-two-providers.psd1'

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner' -IdentityKeys @{ Id = 'user1' }

            $makeProvider = {
                param([string]$Dept)
                $p = [pscustomobject]@{ FixtureDept = $Dept }
                $p | Add-Member -MemberType ScriptMethod -Name GetCapabilities -Value { return @('IdLE.Identity.Read') }
                $p | Add-Member -MemberType ScriptMethod -Name GetIdentity -Value {
                    param([string]$IdentityKey)
                    return @{ IdentityKey = $IdentityKey; Department = $this.FixtureDept }
                }
                return $p
            }

            $providers = @{
                Entra        = & $makeProvider -Dept 'Entra-IT'
                HR           = & $makeProvider -Dept 'HR-IT'
                StepRegistry = @{ 'IdLE.Step.EmitEvent' = 'Invoke-IdleContextResolverTestNoopStep' }
            }

            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

            # Sorted: Entra < HR, so HR (last alphabetically) wins the global view
            $globalProfile = $plan.Request.Context.Views.Identity.Profile
            $globalProfile | Should -Not -BeNullOrEmpty
            $globalProfile.Department | Should -Be 'HR-IT'
            $globalProfile.SourceProvider | Should -Be 'HR'
        }

        It 'provider view contains only the profile for that provider' {
            $wfPath = Join-Path $script:FixturesPath 'resolver-identity-read-two-providers.psd1'

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner' -IdentityKeys @{ Id = 'user1' }

            $makeProvider = {
                param([string]$Dept)
                $p = [pscustomobject]@{ FixtureDept = $Dept }
                $p | Add-Member -MemberType ScriptMethod -Name GetCapabilities -Value { return @('IdLE.Identity.Read') }
                $p | Add-Member -MemberType ScriptMethod -Name GetIdentity -Value {
                    param([string]$IdentityKey)
                    return @{ IdentityKey = $IdentityKey; Department = $this.FixtureDept }
                }
                return $p
            }

            $providers = @{
                Entra        = & $makeProvider -Dept 'Entra-IT'
                HR           = & $makeProvider -Dept 'HR-IT'
                StepRegistry = @{ 'IdLE.Step.EmitEvent' = 'Invoke-IdleContextResolverTestNoopStep' }
            }

            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

            $entraProfile = $plan.Request.Context.Views.Providers.Entra.Identity.Profile
            $entraProfile.Department | Should -Be 'Entra-IT'
            $entraProfile.SourceProvider | Should -Be 'Entra'

            $hrProfile = $plan.Request.Context.Views.Providers.HR.Identity.Profile
            $hrProfile.Department | Should -Be 'HR-IT'
            $hrProfile.SourceProvider | Should -Be 'HR'
        }

        It 'session view (all providers, one auth session) contains the profile for that session' {
            $wfPath = Join-Path $script:FixturesPath 'resolver-identity-read-two-auth-sessions.psd1'

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner' -IdentityKeys @{ Id = 'user1' }

            $provider = [pscustomobject]@{}
            $provider | Add-Member -MemberType ScriptMethod -Name GetCapabilities -Value { return @('IdLE.Identity.Read') }
            $provider | Add-Member -MemberType ScriptMethod -Name GetIdentity -Value {
                param([string]$IdentityKey, [object]$AuthSession)
                return @{ IdentityKey = $IdentityKey; TokenUsed = "$AuthSession" }
            }

            $broker = New-IdleAuthSessionBroker -AuthSessionType 'OAuth' -DefaultAuthSession 'token-corp'
            $broker | Add-Member -MemberType ScriptMethod -Name AcquireAuthSession -Value {
                param([string]$Name, $Options)
                if ($Name -eq 'Corp') { return 'token-corp' }
                if ($Name -eq 'Tier0') { return 'token-tier0' }
                return 'token-default'
            } -Force

            $providers = @{
                Identity          = $provider
                AuthSessionBroker = $broker
                StepRegistry      = @{ 'IdLE.Step.EmitEvent' = 'Invoke-IdleContextResolverTestNoopStep' }
            }

            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

            $corpView = $plan.Request.Context.Views.Sessions.Corp.Identity.Profile
            $corpView.TokenUsed | Should -Be 'token-corp'
            $corpView.SourceAuthSessionName | Should -Be 'Corp'

            $tier0View = $plan.Request.Context.Views.Sessions.Tier0.Identity.Profile
            $tier0View.TokenUsed | Should -Be 'token-tier0'
            $tier0View.SourceAuthSessionName | Should -Be 'Tier0'
        }

        It 'provider+session view contains the exact profile for that provider and session' {
            $wfPath = Join-Path $script:FixturesPath 'resolver-identity-read-two-auth-sessions.psd1'

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner' -IdentityKeys @{ Id = 'user1' }

            $provider = [pscustomobject]@{}
            $provider | Add-Member -MemberType ScriptMethod -Name GetCapabilities -Value { return @('IdLE.Identity.Read') }
            $provider | Add-Member -MemberType ScriptMethod -Name GetIdentity -Value {
                param([string]$IdentityKey, [object]$AuthSession)
                return @{ IdentityKey = $IdentityKey; TokenUsed = "$AuthSession" }
            }

            $broker = New-IdleAuthSessionBroker -AuthSessionType 'OAuth' -DefaultAuthSession 'token-corp'
            $broker | Add-Member -MemberType ScriptMethod -Name AcquireAuthSession -Value {
                param([string]$Name, $Options)
                if ($Name -eq 'Corp') { return 'token-corp' }
                if ($Name -eq 'Tier0') { return 'token-tier0' }
                return 'token-default'
            } -Force

            $providers = @{
                Identity          = $provider
                AuthSessionBroker = $broker
                StepRegistry      = @{ 'IdLE.Step.EmitEvent' = 'Invoke-IdleContextResolverTestNoopStep' }
            }

            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

            $identityCorpView = $plan.Request.Context.Views.Providers.Identity.Sessions.Corp.Identity.Profile
            $identityCorpView.TokenUsed | Should -Be 'token-corp'
            $identityCorpView.SourceProvider | Should -Be 'Identity'
            $identityCorpView.SourceAuthSessionName | Should -Be 'Corp'

            $identityTier0View = $plan.Request.Context.Views.Providers.Identity.Sessions.Tier0.Identity.Profile
            $identityTier0View.TokenUsed | Should -Be 'token-tier0'
            $identityTier0View.SourceAuthSessionName | Should -Be 'Tier0'
        }
    }

    Context 'Fail-fast on invalid path segments' {
        It 'fails when provider alias contains a dot (invalid path segment)' {
            $wfPath = Join-Path $script:FixturesPath 'resolver-invalid-provider-alias.psd1'

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner'

            # Provider with a dot in its alias - not a valid path segment
            $p = [pscustomobject]@{}
            $p | Add-Member -MemberType ScriptMethod -Name GetCapabilities -Value { return @('IdLE.Entitlement.List') }
            $p | Add-Member -MemberType ScriptMethod -Name ListEntitlements -Value { param([string]$IdentityKey) return @() }

            $providers = @{
                'Invalid.Alias' = $p
                StepRegistry    = @{ 'IdLE.Step.EmitEvent' = 'Invoke-IdleContextResolverTestNoopStep' }
            }

            { New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers } |
                Should -Throw -ExpectedMessage "*not a valid context path segment*"
        }

        It 'fails when AuthSessionName contains a dot (invalid path segment)' {
            $wfPath = Join-Path $script:FixturesPath 'resolver-invalid-auth-session.psd1'

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner'

            $provider = [pscustomobject]@{}
            $provider | Add-Member -MemberType ScriptMethod -Name GetCapabilities -Value { return @('IdLE.Entitlement.List') }
            $provider | Add-Member -MemberType ScriptMethod -Name ListEntitlements -Value {
                param([string]$IdentityKey, [object]$AuthSession)
                return @()
            }

            $broker = New-IdleAuthSessionBroker -AuthSessionType 'OAuth' -DefaultAuthSession 'test-token'

            $providers = @{
                Identity          = $provider
                AuthSessionBroker = $broker
                StepRegistry      = @{ 'IdLE.Step.EmitEvent' = 'Invoke-IdleContextResolverTestNoopStep' }
            }

            { New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers } |
                Should -Throw -ExpectedMessage "*not a valid context path segment*"
        }
    }

    Context 'View stale-data regression (empty and null results)' {
        It 'entitlement global view is an empty array when the resolver returns no items' {
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

            # Global view must be written as empty array, not absent.
            # Use Contains() because -BeNullOrEmpty also matches @() (empty array).
            $plan.Request.Context.Views.Identity.Contains('Entitlements') | Should -BeTrue -Because 'global view key must be present even when empty'
            @($plan.Request.Context.Views.Identity.Entitlements).Count | Should -Be 0

            # Per-provider view must also be written.
            $plan.Request.Context.Views.Providers.Identity.Identity.Contains('Entitlements') | Should -BeTrue -Because 'provider view key must be present even when empty'
            @($plan.Request.Context.Views.Providers.Identity.Identity.Entitlements).Count | Should -Be 0
        }

        It 'entitlement provider view is written as empty array when that provider returns no items' {
            $wfPath = Join-Path $script:FixturesPath 'resolver-two-providers.psd1'

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner' -IdentityKeys @{ Id = 'user1' }

            $entraProvider = [pscustomobject]@{}
            $entraProvider | Add-Member -MemberType ScriptMethod -Name GetCapabilities -Value { return @('IdLE.Entitlement.List') }
            $entraProvider | Add-Member -MemberType ScriptMethod -Name ListEntitlements -Value {
                param([string]$IdentityKey)
                return @(@{ Kind = 'Group'; Id = 'grp-entra' })
            }

            $adProvider = [pscustomobject]@{}
            $adProvider | Add-Member -MemberType ScriptMethod -Name GetCapabilities -Value { return @('IdLE.Entitlement.List') }
            $adProvider | Add-Member -MemberType ScriptMethod -Name ListEntitlements -Value {
                param([string]$IdentityKey)
                return @()  # AD returns no entitlements
            }

            $providers = @{
                Entra        = $entraProvider
                AD           = $adProvider
                StepRegistry = @{ 'IdLE.Step.EmitEvent' = 'Invoke-IdleContextResolverTestNoopStep' }
            }

            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

            # Global view has Entra's entitlement
            @($plan.Request.Context.Views.Identity.Entitlements).Count | Should -Be 1

            # AD provider view must be written (as empty array), not absent.
            # Use Contains() because -BeNullOrEmpty also matches @() (empty array).
            $plan.Request.Context.Views.Providers.AD.Identity.Contains('Entitlements') | Should -BeTrue -Because 'AD provider view key must be present even when empty'
            @($plan.Request.Context.Views.Providers.AD.Identity.Entitlements).Count | Should -Be 0

            # AD default session provider+session view must also be written.
            $plan.Request.Context.Views.Providers.AD.Sessions.Default.Identity.Contains('Entitlements') | Should -BeTrue -Because 'AD provider+session view key must be present even when empty'
            @($plan.Request.Context.Views.Providers.AD.Sessions.Default.Identity.Entitlements).Count | Should -Be 0
        }

        It 'profile provider view is written as null when that provider returns no profile' {
            $wfPath = Join-Path $script:FixturesPath 'resolver-identity-read-two-providers.psd1'

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner' -IdentityKeys @{ Id = 'user1' }

            $makeProvider = {
                param([object]$ProfileToReturn)
                $p = [pscustomobject]@{ ProfileData = $ProfileToReturn }
                $p | Add-Member -MemberType ScriptMethod -Name GetCapabilities -Value { return @('IdLE.Identity.Read') }
                $p | Add-Member -MemberType ScriptMethod -Name GetIdentity -Value {
                    param([string]$IdentityKey)
                    return $this.ProfileData
                }
                return $p
            }

            $providers = @{
                Entra        = & $makeProvider -ProfileToReturn @{ IdentityKey = 'user1'; Source = 'Entra' }
                HR           = & $makeProvider -ProfileToReturn $null  # HR finds no profile
                StepRegistry = @{ 'IdLE.Step.EmitEvent' = 'Invoke-IdleContextResolverTestNoopStep' }
            }

            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

            # Global view: last-non-null wins → Entra wins (HR returned null)
            $plan.Request.Context.Views.Identity.Profile | Should -Not -BeNullOrEmpty
            $plan.Request.Context.Views.Identity.Profile.Source | Should -Be 'Entra'

            # HR provider view must be present as null (not absent)
            $hrViewPresent = $plan.Request.Context.Views.Contains('Providers') -and
                             $plan.Request.Context.Views.Providers.Contains('HR')
            $hrViewPresent | Should -BeTrue -Because 'HR provider view node must be present'
            $plan.Request.Context.Views.Providers.HR.Identity.Profile | Should -BeNullOrEmpty

            # HR provider+session view must be present as null
            $hrSessionViewPresent = $plan.Request.Context.Views.Providers.HR.Contains('Sessions') -and
                                    $plan.Request.Context.Views.Providers.HR.Sessions.Contains('Default')
            $hrSessionViewPresent | Should -BeTrue -Because 'HR provider+session view node must be present'
            $plan.Request.Context.Views.Providers.HR.Sessions.Default.Identity.Profile | Should -BeNullOrEmpty
        }
    }

    Context 'Request.Context.Current alias (execution-time preconditions)' {
        It 'Current resolves to the step provider/auth scoped context during precondition evaluation' {
            $wfPath = Join-Path $script:FixturesPath 'resolver-current-precondition.psd1'

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner'

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

            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers
            $result = Invoke-IdlePlan -Plan $plan -Providers $providers

            $result | Should -Not -BeNullOrEmpty
            # Step should have executed (precondition passed via Current path)
            $stepResult = $result.Steps | Where-Object { $_.Name -eq 'CurrentPreconditionStep' }
            $stepResult | Should -Not -BeNullOrEmpty
            $stepResult.Status | Should -Be 'Completed'
        }
    }
}

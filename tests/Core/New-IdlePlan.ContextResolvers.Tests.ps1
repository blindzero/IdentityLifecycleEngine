Set-StrictMode -Version Latest

BeforeAll {
    . (Join-Path (Split-Path -Path $PSScriptRoot -Parent) '_testHelpers.ps1')
    Import-IdleTestModule

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
            $wfPath = New-IdleTestWorkflowFile -FileName 'resolver-condition.psd1' -Content @'
@{
  Name           = 'Resolver Condition Test'
  LifecycleEvent = 'Joiner'
  ContextResolvers = @(
    @{
      Capability = 'IdLE.Entitlement.List'
      Provider   = 'Identity'
      With       = @{ IdentityKey = 'user1' }
      To         = 'Context.Identity.Entitlements'
    }
  )
  Steps = @(
    @{
      Name      = 'ConditionalStep'
      Type      = 'IdLE.Step.EmitEvent'
      Condition = @{ Exists = 'Request.Context.Identity.Entitlements' }
    }
  )
}
'@

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner' -IdentityKeys @{ Id = 'user1' }

            $provider = New-IdleMockIdentityProvider -InitialStore @{
                'user1' = @{
                    IdentityKey  = 'user1'
                    Enabled      = $true
                    Attributes   = @{}
                    Entitlements = @(
                        @{ Kind = 'Group'; Id = 'g1'; DisplayName = 'Group 1' }
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

            # Snapshot captures resolved context
            $plan.Request.Context | Should -Not -BeNullOrEmpty
            $plan.Request.Context.Identity | Should -Not -BeNullOrEmpty
            $entitlements = @($plan.Request.Context.Identity.Entitlements)
            $entitlements.Count | Should -Be 1
            $entitlements[0].Id | Should -Be 'g1'
        }

        It 'step is NotApplicable when resolver returns empty entitlements and condition requires them' {
            $wfPath = New-IdleTestWorkflowFile -FileName 'resolver-empty.psd1' -Content @'
@{
  Name           = 'Resolver Empty Test'
  LifecycleEvent = 'Joiner'
  ContextResolvers = @(
    @{
      Capability = 'IdLE.Entitlement.List'
      Provider   = 'Identity'
      With       = @{ IdentityKey = 'user2' }
      To         = 'Context.Identity.Entitlements'
    }
  )
  Steps = @(
    @{
      Name      = 'NeedsEntitlements'
      Type      = 'IdLE.Step.EmitEvent'
      Condition = @{ Exists = 'Request.Context.Identity.Entitlements' }
    }
  )
}
'@

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
    }

    Context 'To path validation' {
        It 'rejects To value outside Context. namespace' {
            $wfPath = New-IdleTestWorkflowFile -FileName 'resolver-bad-to.psd1' -Content @'
@{
  Name           = 'Bad To Test'
  LifecycleEvent = 'Joiner'
  ContextResolvers = @(
    @{
      Capability = 'IdLE.Entitlement.List'
      With       = @{ IdentityKey = 'user1' }
      To         = 'Intent.Entitlements'
    }
  )
  Steps = @(
    @{ Name = 'Step1'; Type = 'IdLE.Step.EmitEvent' }
  )
}
'@

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner'

            { New-IdlePlan -WorkflowPath $wfPath -Request $req } |
                Should -Throw -ExpectedMessage "*must start with 'Context.'*"
        }

        It 'rejects To = Context. without a sub-path' {
            $wfPath = New-IdleTestWorkflowFile -FileName 'resolver-bare-context.psd1' -Content @'
@{
  Name           = 'Bare Context To Test'
  LifecycleEvent = 'Joiner'
  ContextResolvers = @(
    @{
      Capability = 'IdLE.Entitlement.List'
      With       = @{ IdentityKey = 'user1' }
      To         = 'Context.'
    }
  )
  Steps = @(
    @{ Name = 'Step1'; Type = 'IdLE.Step.EmitEvent' }
  )
}
'@

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner'

            # Schema validation rejects empty sub-path (starts with 'Context.' but nothing after)
            { New-IdlePlan -WorkflowPath $wfPath -Request $req } | Should -Throw
        }
    }

    Context 'Non-allow-listed capability' {
        It 'rejects a resolver that uses a capability not in the read-only allow-list' {
            $wfPath = New-IdleTestWorkflowFile -FileName 'resolver-mutating-cap.psd1' -Content @'
@{
  Name           = 'Mutating Capability Test'
  LifecycleEvent = 'Joiner'
  ContextResolvers = @(
    @{
      Capability = 'IdLE.Entitlement.Grant'
      With       = @{ IdentityKey = 'user1' }
      To         = 'Context.Result'
    }
  )
  Steps = @(
    @{ Name = 'Step1'; Type = 'IdLE.Step.EmitEvent' }
  )
}
'@

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner'

            { New-IdlePlan -WorkflowPath $wfPath -Request $req } |
                Should -Throw -ExpectedMessage "*not in the read-only allow-list*"
        }
    }

    Context 'Resolver output captured in plan snapshot' {
        It 'plan.Request.Context contains the resolved value after planning' {
            $wfPath = New-IdleTestWorkflowFile -FileName 'resolver-snapshot.psd1' -Content @'
@{
  Name           = 'Snapshot Test'
  LifecycleEvent = 'Joiner'
  ContextResolvers = @(
    @{
      Capability = 'IdLE.Entitlement.List'
      Provider   = 'Identity'
      With       = @{ IdentityKey = 'snap-user' }
      To         = 'Context.Snap.Entitlements'
    }
  )
  Steps = @(
    @{ Name = 'Step1'; Type = 'IdLE.Step.EmitEvent' }
  )
}
'@

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner'

            $provider = New-IdleMockIdentityProvider -InitialStore @{
                'snap-user' = @{
                    IdentityKey  = 'snap-user'
                    Enabled      = $true
                    Attributes   = @{}
                    Entitlements = @(
                        @{ Kind = 'Role'; Id = 'admin'; DisplayName = 'Admin Role' }
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
            $plan.Request.Context.Snap | Should -Not -BeNullOrEmpty
            $snap = @($plan.Request.Context.Snap.Entitlements)
            $snap.Count | Should -Be 1
            $snap[0].Kind | Should -Be 'Role'
            $snap[0].Id | Should -Be 'admin'
        }
    }

    Context 'Provider auto-selection' {
        It 'auto-selects provider when Provider is not specified in resolver' {
            $wfPath = New-IdleTestWorkflowFile -FileName 'resolver-autoselect.psd1' -Content @'
@{
  Name           = 'Auto Select Test'
  LifecycleEvent = 'Joiner'
  ContextResolvers = @(
    @{
      Capability = 'IdLE.Entitlement.List'
      With       = @{ IdentityKey = 'auto-user' }
      To         = 'Context.Identity.Entitlements'
    }
  )
  Steps = @(
    @{ Name = 'Step1'; Type = 'IdLE.Step.EmitEvent' }
  )
}
'@

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner'

            $provider = New-IdleMockIdentityProvider -InitialStore @{
                'auto-user' = @{
                    IdentityKey  = 'auto-user'
                    Enabled      = $true
                    Attributes   = @{}
                    Entitlements = @(
                        @{ Kind = 'Group'; Id = 'grp-auto'; DisplayName = 'Auto Group' }
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
            $wfPath = New-IdleTestWorkflowFile -FileName 'resolver-no-provider.psd1' -Content @'
@{
  Name           = 'No Provider Test'
  LifecycleEvent = 'Joiner'
  ContextResolvers = @(
    @{
      Capability = 'IdLE.Entitlement.List'
      With       = @{ IdentityKey = 'user1' }
      To         = 'Context.Identity.Entitlements'
    }
  )
  Steps = @(
    @{ Name = 'Step1'; Type = 'IdLE.Step.EmitEvent' }
  )
}
'@

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
            $wfPath = New-IdleTestWorkflowFile -FileName 'resolver-unknown-key.psd1' -Content @'
@{
  Name           = 'Unknown Key Test'
  LifecycleEvent = 'Joiner'
  ContextResolvers = @(
    @{
      Capability = 'IdLE.Entitlement.List'
      With       = @{ IdentityKey = 'user1' }
      To         = 'Context.Identity.Entitlements'
      UnknownKey = 'bad'
    }
  )
  Steps = @(
    @{ Name = 'Step1'; Type = 'IdLE.Step.EmitEvent' }
  )
}
'@

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner'

            { New-IdlePlan -WorkflowPath $wfPath -Request $req } |
                Should -Throw -ExpectedMessage "*Unknown key*UnknownKey*"
        }

        It 'rejects a resolver missing the required Capability key' {
            $wfPath = New-IdleTestWorkflowFile -FileName 'resolver-missing-cap.psd1' -Content @'
@{
  Name           = 'Missing Capability Test'
  LifecycleEvent = 'Joiner'
  ContextResolvers = @(
    @{
      With = @{ IdentityKey = 'user1' }
      To   = 'Context.Identity.Entitlements'
    }
  )
  Steps = @(
    @{ Name = 'Step1'; Type = 'IdLE.Step.EmitEvent' }
  )
}
'@

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner'

            { New-IdlePlan -WorkflowPath $wfPath -Request $req } |
                Should -Throw -ExpectedMessage "*Capability*"
        }

        It 'rejects a resolver missing the required To key' {
            $wfPath = New-IdleTestWorkflowFile -FileName 'resolver-missing-to.psd1' -Content @'
@{
  Name           = 'Missing To Test'
  LifecycleEvent = 'Joiner'
  ContextResolvers = @(
    @{
      Capability = 'IdLE.Entitlement.List'
      With       = @{ IdentityKey = 'user1' }
    }
  )
  Steps = @(
    @{ Name = 'Step1'; Type = 'IdLE.Step.EmitEvent' }
  )
}
'@

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner'

            { New-IdlePlan -WorkflowPath $wfPath -Request $req } |
                Should -Throw -ExpectedMessage "*To*"
        }
    }

    Context 'Template resolution in With' {
        It 'resolves Request.IdentityKeys template in With.IdentityKey' {
            $wfPath = New-IdleTestWorkflowFile -FileName 'resolver-template.psd1' -Content @'
@{
  Name           = 'Template Test'
  LifecycleEvent = 'Joiner'
  ContextResolvers = @(
    @{
      Capability = 'IdLE.Entitlement.List'
      Provider   = 'Identity'
      With       = @{ IdentityKey = '{{Request.IdentityKeys.Id}}' }
      To         = 'Context.Identity.Entitlements'
    }
  )
  Steps = @(
    @{ Name = 'Step1'; Type = 'IdLE.Step.EmitEvent' }
  )
}
'@

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner' -IdentityKeys @{ Id = 'tmpl-user' }

            $provider = New-IdleMockIdentityProvider -InitialStore @{
                'tmpl-user' = @{
                    IdentityKey  = 'tmpl-user'
                    Enabled      = $true
                    Attributes   = @{}
                    Entitlements = @(
                        @{ Kind = 'Group'; Id = 'tmpl-grp'; DisplayName = 'Template Group' }
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

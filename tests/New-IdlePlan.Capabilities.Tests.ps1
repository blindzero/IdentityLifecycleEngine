BeforeAll {
    . (Join-Path $PSScriptRoot '_testHelpers.ps1')
    Import-IdleTestModule
}

Describe 'New-IdlePlan - required provider capabilities' {

    It 'fails fast when a step requires capabilities that no provider advertises' {
        $wfPath = Join-Path -Path $TestDrive -ChildPath 'joiner-capabilities.psd1'

        Set-Content -Path $wfPath -Encoding UTF8 -Value @'
@{
  Name           = 'Joiner - Capability Validation'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name                 = 'Disable identity'
      Type                 = 'IdLE.Step.DisableIdentity'
      RequiresCapabilities = @('IdLE.Identity.Disable')
    }
  )
}
'@

        $req = New-IdleLifecycleRequest -LifecycleEvent 'Joiner'

        try {
            New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers @{} | Out-Null
            throw 'Expected an exception but none was thrown.'
        }
        catch {
            $_.Exception.Message | Should -Match 'MissingCapabilities: IdLE\.Identity\.Disable'
            $_.Exception.Message | Should -Match 'AffectedSteps: Disable identity'
        }
    }

    It 'allows planning when a provider advertises the required capabilities' {
        $wfPath = Join-Path -Path $TestDrive -ChildPath 'joiner-capabilities-ok.psd1'

        Set-Content -Path $wfPath -Encoding UTF8 -Value @'
@{
  Name           = 'Joiner - Capability Validation OK'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name                 = 'Disable identity'
      Type                 = 'IdLE.Step.DisableIdentity'
      RequiresCapabilities = @('IdLE.Identity.Disable')
    }
  )
}
'@

        $req = New-IdleLifecycleRequest -LifecycleEvent 'Joiner'

        $provider = [pscustomobject]@{ Name = 'IdentityProvider' }
        $provider | Add-Member -MemberType ScriptMethod -Name GetCapabilities -Value {
            return @('IdLE.Identity.Disable')
        } -Force

        $providers = @{
            IdentityProvider = $provider
        }

        $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

        $plan | Should -Not -BeNullOrEmpty
        $plan.Steps.Count | Should -Be 1
        $plan.Steps[0].RequiresCapabilities | Should -Be @('IdLE.Identity.Disable')
    }

    It 'fails fast when an OnFailure step requires capabilities that no provider advertises' {
        $wfPath = Join-Path -Path $TestDrive -ChildPath 'joiner-onfailure-capabilities.psd1'

        Set-Content -Path $wfPath -Encoding UTF8 -Value @'
@{
  Name           = 'Joiner - OnFailure Capability Validation'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'Primary step'
      Type = 'IdLE.Step.Primary'
    }
  )
  OnFailureSteps = @(
    @{
      Name                 = 'Containment'
      Type                 = 'IdLE.Step.Containment'
      RequiresCapabilities = @('IdLE.Identity.Disable')
    }
  )
}
'@

        $req = New-IdleLifecycleRequest -LifecycleEvent 'Joiner'

        try {
            New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers @{} | Out-Null
            throw 'Expected an exception but none was thrown.'
        }
        catch {
            $_.Exception.Message | Should -Match 'MissingCapabilities: IdLE\.Identity\.Disable'
            $_.Exception.Message | Should -Match 'AffectedSteps: Containment'
        }
    }

    It 'includes OnFailureSteps capability requirements in successful planning' {
        $wfPath = Join-Path -Path $TestDrive -ChildPath 'joiner-onfailure-capabilities-ok.psd1'

        Set-Content -Path $wfPath -Encoding UTF8 -Value @'
@{
  Name           = 'Joiner - OnFailure Capability Validation OK'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'Primary step'
      Type = 'IdLE.Step.Primary'
    }
  )
  OnFailureSteps = @(
    @{
      Name                 = 'Containment'
      Type                 = 'IdLE.Step.Containment'
      RequiresCapabilities = @('IdLE.Identity.Disable')
    }
  )
}
'@

        $req = New-IdleLifecycleRequest -LifecycleEvent 'Joiner'

        $provider = [pscustomobject]@{ Name = 'IdentityProvider' }
        $provider | Add-Member -MemberType ScriptMethod -Name GetCapabilities -Value {
            return @('IdLE.Identity.Disable')
        } -Force

        $providers = @{
            IdentityProvider = $provider
        }

        $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

        $plan | Should -Not -BeNullOrEmpty
        $plan.OnFailureSteps.Count | Should -Be 1
        $plan.OnFailureSteps[0].RequiresCapabilities | Should -Be @('IdLE.Identity.Disable')
    }

    It 'validates entitlement capabilities for EnsureEntitlement steps' {
        $wfPath = Join-Path -Path $TestDrive -ChildPath 'joiner-entitlements.psd1'

        Set-Content -Path $wfPath -Encoding UTF8 -Value @'
@{
  Name           = 'Joiner - Entitlement Capability Validation'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name                 = 'Ensure group membership'
      Type                 = 'IdLE.Step.EnsureEntitlement'
      With                 = @{ IdentityKey = 'user1'; Entitlement = @{ Kind = 'Group'; Id = 'demo-group' }; State = 'Present' }
      RequiresCapabilities = @('IdLE.Entitlement.List', 'IdLE.Entitlement.Grant')
    }
  )
}
'@

        $req = New-IdleLifecycleRequest -LifecycleEvent 'Joiner'

        try {
            New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers @{} | Out-Null
            throw 'Expected an exception but none was thrown.'
        }
        catch {
            $_.Exception.Message | Should -Match 'MissingCapabilities: IdLE\.Entitlement\.Grant, IdLE\.Entitlement\.List'
        }

        $provider = [pscustomobject]@{ Name = 'EntProvider' }
        $provider | Add-Member -MemberType ScriptMethod -Name GetCapabilities -Value {
            return @('IdLE.Entitlement.List', 'IdLE.Entitlement.Grant')
        } -Force

        $providers = @{ Entitlement = $provider }

        $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

        $plan | Should -Not -BeNullOrEmpty
        $plan.Steps.Count | Should -Be 1
        $plan.Steps[0].RequiresCapabilities | Should -Be @('IdLE.Entitlement.Grant', 'IdLE.Entitlement.List')
    }

    It 'accepts legacy capability names and normalizes them to canonical form' {
        $wfPath = Join-Path -Path $TestDrive -ChildPath 'joiner-legacy-capabilities.psd1'

        Set-Content -Path $wfPath -Encoding UTF8 -Value @'
@{
  Name           = 'Joiner - Legacy Capability Names'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name                 = 'Disable identity'
      Type                 = 'IdLE.Step.DisableIdentity'
      RequiresCapabilities = @('Identity.Disable')
    }
  )
}
'@

        $req = New-IdleLifecycleRequest -LifecycleEvent 'Joiner'

        $provider = [pscustomobject]@{ Name = 'IdentityProvider' }
        $provider | Add-Member -MemberType ScriptMethod -Name GetCapabilities -Value {
            return @('IdLE.Identity.Disable')
        } -Force

        $providers = @{
            IdentityProvider = $provider
        }

        # Legacy capability name in workflow should be accepted and normalized
        $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

        $plan | Should -Not -BeNullOrEmpty
        $plan.Steps.Count | Should -Be 1
        # The capability should be normalized to canonical form in the plan
        $plan.Steps[0].RequiresCapabilities | Should -Be @('IdLE.Identity.Disable')
    }

    It 'accepts legacy capability names from provider and normalizes them' {
        $wfPath = Join-Path -Path $TestDrive -ChildPath 'joiner-legacy-provider.psd1'

        Set-Content -Path $wfPath -Encoding UTF8 -Value @'
@{
  Name           = 'Joiner - Legacy Provider Capabilities'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name                 = 'Disable identity'
      Type                 = 'IdLE.Step.DisableIdentity'
      RequiresCapabilities = @('IdLE.Identity.Disable')
    }
  )
}
'@

        $req = New-IdleLifecycleRequest -LifecycleEvent 'Joiner'

        $provider = [pscustomobject]@{ Name = 'LegacyProvider' }
        $provider | Add-Member -MemberType ScriptMethod -Name GetCapabilities -Value {
            # Provider advertises legacy capability name
            return @('Identity.Disable')
        } -Force

        $providers = @{
            IdentityProvider = $provider
        }

        # Legacy capability from provider should be normalized and match the canonical requirement
        $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

        $plan | Should -Not -BeNullOrEmpty
        $plan.Steps.Count | Should -Be 1
        $plan.Steps[0].RequiresCapabilities | Should -Be @('IdLE.Identity.Disable')
    }
}

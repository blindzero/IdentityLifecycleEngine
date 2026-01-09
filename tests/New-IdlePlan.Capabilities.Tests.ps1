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
      RequiresCapabilities = @('Identity.Disable')
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
            $_.Exception.Message | Should -Match 'MissingCapabilities: Identity\.Disable'
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
      RequiresCapabilities = @('Identity.Disable')
    }
  )
}
'@

        $req = New-IdleLifecycleRequest -LifecycleEvent 'Joiner'

        $provider = [pscustomobject]@{ Name = 'IdentityProvider' }
        $provider | Add-Member -MemberType ScriptMethod -Name GetCapabilities -Value {
            return @('Identity.Disable')
        } -Force

        $providers = @{
            IdentityProvider = $provider
        }

        $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

        $plan | Should -Not -BeNullOrEmpty
        $plan.Steps.Count | Should -Be 1
        $plan.Steps[0].RequiresCapabilities | Should -Be @('Identity.Disable')
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
      RequiresCapabilities = @('Identity.Disable')
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
            $_.Exception.Message | Should -Match 'MissingCapabilities: Identity\.Disable'
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
      RequiresCapabilities = @('Identity.Disable')
    }
  )
}
'@

        $req = New-IdleLifecycleRequest -LifecycleEvent 'Joiner'

        $provider = [pscustomobject]@{ Name = 'IdentityProvider' }
        $provider | Add-Member -MemberType ScriptMethod -Name GetCapabilities -Value {
            return @('Identity.Disable')
        } -Force

        $providers = @{
            IdentityProvider = $provider
        }

        $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

        $plan | Should -Not -BeNullOrEmpty
        $plan.OnFailureSteps.Count | Should -Be 1
        $plan.OnFailureSteps[0].RequiresCapabilities | Should -Be @('Identity.Disable')
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
}

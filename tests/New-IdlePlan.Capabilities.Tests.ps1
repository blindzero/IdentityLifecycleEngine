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
      Type                 = 'IdLE.Step.EmitEvent'
      With                 = @{ Message = 'Disable identity (planning only test)' }
      RequiresCapabilities = 'Identity.Disable'
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
            $_.Exception.Message | Should -Match 'required provider capabilities are missing'
            $_.Exception.Message | Should -Match 'MissingCapabilities:\s+Identity\.Disable'
            $_.Exception.Message | Should -Match 'AffectedSteps:\s+Disable identity'
        }
    }

    It 'builds the plan when required capabilities are available' {
        $wfPath = Join-Path -Path $TestDrive -ChildPath 'joiner-capabilities.psd1'

        Set-Content -Path $wfPath -Encoding UTF8 -Value @'
@{
  Name           = 'Joiner - Capability Validation'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name                 = 'Disable identity'
      Type                 = 'IdLE.Step.EmitEvent'
      With                 = @{ Message = 'Disable identity (planning only test)' }
      RequiresCapabilities = 'Identity.Disable'
    }
  )
}
'@

        $req = New-IdleLifecycleRequest -LifecycleEvent 'Joiner'

        # Minimal provider that advertises the required capability.
        $provider = [pscustomobject]@{
            Name = 'TestProvider'
        }
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
}

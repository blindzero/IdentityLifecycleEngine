BeforeAll {
    . (Join-Path $PSScriptRoot '_testHelpers.ps1')
    Import-IdleTestModule
}

Describe 'New-IdlePlan - required provider capabilities' {

    It 'rejects workflows containing RequiresCapabilities' {
        $wfPath = Join-Path -Path $TestDrive -ChildPath 'joiner-legacy.psd1'

        Set-Content -Path $wfPath -Encoding UTF8 -Value @'
@{
  Name           = 'Joiner - Legacy Workflow'
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
            $_.Exception.Message | Should -Match 'RequiresCapabilities'
            $_.Exception.Message | Should -Match 'not allowed'
        }
    }

    It 'fails fast when a step type has no metadata entry' {
        $wfPath = Join-Path -Path $TestDrive -ChildPath 'joiner-no-metadata.psd1'

        Set-Content -Path $wfPath -Encoding UTF8 -Value @'
@{
  Name           = 'Joiner - Missing Metadata'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'Unknown step'
      Type = 'Custom.Step.Unknown'
    }
  )
}
'@

        $req = New-IdleLifecycleRequest -LifecycleEvent 'Joiner'

        # Provide a custom StepRegistry for the unknown step type
        $providers = @{
            StepRegistry = @{
                'Custom.Step.Unknown' = 'Invoke-CustomStepUnknown'
            }
        }

        try {
            New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers | Out-Null
            throw 'Expected an exception but none was thrown.'
        }
        catch {
            $_.Exception.Message | Should -Match 'no StepMetadata entry'
            $_.Exception.Message | Should -Match 'Custom.Step.Unknown'
        }
    }

    It 'derives capabilities from built-in step metadata' {
        $wfPath = Join-Path -Path $TestDrive -ChildPath 'joiner-builtin.psd1'

        Set-Content -Path $wfPath -Encoding UTF8 -Value @'
@{
  Name           = 'Joiner - Built-in Metadata'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'Disable identity'
      Type = 'IdLE.Step.DisableIdentity'
    }
  )
}
'@

        $req = New-IdleLifecycleRequest -LifecycleEvent 'Joiner'

        $provider = [pscustomobject]@{ Name = 'IdentityProvider' }
        $provider | Add-Member -MemberType ScriptMethod -Name GetCapabilities -Value {
            return @('IdLE.Identity.Disable', 'IdLE.Identity.Read')
        } -Force

        $providers = @{
            IdentityProvider = $provider
        }

        $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

        $plan | Should -Not -BeNullOrEmpty
        $plan.Steps.Count | Should -Be 1
        $plan.Steps[0].RequiresCapabilities | Should -Contain 'IdLE.Identity.Disable'
        $plan.Steps[0].RequiresCapabilities | Should -Contain 'IdLE.Identity.Read'
    }

    It 'fails fast when required capabilities are missing' {
        $wfPath = Join-Path -Path $TestDrive -ChildPath 'joiner-missing-caps.psd1'

        Set-Content -Path $wfPath -Encoding UTF8 -Value @'
@{
  Name           = 'Joiner - Missing Capabilities'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'Disable identity'
      Type = 'IdLE.Step.DisableIdentity'
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
            $_.Exception.Message | Should -Match 'MissingCapabilities'
            $_.Exception.Message | Should -Match 'IdLE\.Identity\.Disable'
            $_.Exception.Message | Should -Match 'AffectedSteps: Disable identity'
        }
    }

    It 'allows host metadata to override built-in metadata' {
        $wfPath = Join-Path -Path $TestDrive -ChildPath 'joiner-override.psd1'

        Set-Content -Path $wfPath -Encoding UTF8 -Value @'
@{
  Name           = 'Joiner - Override Metadata'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'Disable identity'
      Type = 'IdLE.Step.DisableIdentity'
    }
  )
}
'@

        $req = New-IdleLifecycleRequest -LifecycleEvent 'Joiner'

        $provider = [pscustomobject]@{ Name = 'IdentityProvider' }
        $provider | Add-Member -MemberType ScriptMethod -Name GetCapabilities -Value {
            return @('Custom.Capability.Override')
        } -Force

        $providers = @{
            IdentityProvider = $provider
            StepMetadata     = @{
                'IdLE.Step.DisableIdentity' = @{
                    RequiredCapabilities = @('Custom.Capability.Override')
                }
            }
        }

        $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

        $plan | Should -Not -BeNullOrEmpty
        $plan.Steps.Count | Should -Be 1
        $plan.Steps[0].RequiresCapabilities | Should -Be @('Custom.Capability.Override')
    }

    It 'validates OnFailureSteps capabilities from metadata' {
        $wfPath = Join-Path -Path $TestDrive -ChildPath 'joiner-onfailure.psd1'

        Set-Content -Path $wfPath -Encoding UTF8 -Value @'
@{
  Name           = 'Joiner - OnFailure Metadata'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'Primary step'
      Type = 'IdLE.Step.EmitEvent'
      With = @{ Message = 'Primary' }
    }
  )
  OnFailureSteps = @(
    @{
      Name = 'Containment'
      Type = 'IdLE.Step.DisableIdentity'
    }
  )
}
'@

        $req = New-IdleLifecycleRequest -LifecycleEvent 'Joiner'

        $provider = [pscustomobject]@{ Name = 'IdentityProvider' }
        $provider | Add-Member -MemberType ScriptMethod -Name GetCapabilities -Value {
            return @('IdLE.Identity.Disable', 'IdLE.Identity.Read')
        } -Force

        $providers = @{
            IdentityProvider = $provider
        }

        $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

        $plan | Should -Not -BeNullOrEmpty
        $plan.OnFailureSteps.Count | Should -Be 1
        $plan.OnFailureSteps[0].RequiresCapabilities | Should -Contain 'IdLE.Identity.Disable'
        $plan.OnFailureSteps[0].RequiresCapabilities | Should -Contain 'IdLE.Identity.Read'
    }

    It 'validates entitlement capabilities from metadata' {
        $wfPath = Join-Path -Path $TestDrive -ChildPath 'joiner-entitlements.psd1'

        Set-Content -Path $wfPath -Encoding UTF8 -Value @'
@{
  Name           = 'Joiner - Entitlement Metadata'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'Ensure group membership'
      Type = 'IdLE.Step.EnsureEntitlement'
      With = @{ IdentityKey = 'user1'; Entitlement = @{ Kind = 'Group'; Id = 'demo-group' }; State = 'Present' }
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
            $_.Exception.Message | Should -Match 'MissingCapabilities'
            $_.Exception.Message | Should -Match 'IdLE\.Entitlement'
        }

        $provider = [pscustomobject]@{ Name = 'EntProvider' }
        $provider | Add-Member -MemberType ScriptMethod -Name GetCapabilities -Value {
            return @('IdLE.Entitlement.List', 'IdLE.Entitlement.Grant', 'IdLE.Entitlement.Revoke')
        } -Force

        $providers = @{ Entitlement = $provider }

        $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

        $plan | Should -Not -BeNullOrEmpty
        $plan.Steps.Count | Should -Be 1
        $plan.Steps[0].RequiresCapabilities | Should -Contain 'IdLE.Entitlement.List'
        $plan.Steps[0].RequiresCapabilities | Should -Contain 'IdLE.Entitlement.Grant'
        $plan.Steps[0].RequiresCapabilities | Should -Contain 'IdLE.Entitlement.Revoke'
    }

    It 'rejects metadata with ScriptBlock values' {
        $wfPath = Join-Path -Path $TestDrive -ChildPath 'joiner-scriptblock.psd1'

        Set-Content -Path $wfPath -Encoding UTF8 -Value @'
@{
  Name           = 'Joiner - ScriptBlock Test'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'Test step'
      Type = 'Custom.Step.Test'
    }
  )
}
'@

        $req = New-IdleLifecycleRequest -LifecycleEvent 'Joiner'

        $providers = @{
            StepRegistry = @{
                'Custom.Step.Test' = 'Invoke-CustomStep'
            }
            StepMetadata = @{
                'Custom.Step.Test' = @{
                    RequiredCapabilities = { 'Dynamic.Capability' }
                }
            }
        }

        try {
            New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers | Out-Null
            throw 'Expected an exception but none was thrown.'
        }
        catch {
            $_.Exception.Message | Should -Match 'ScriptBlock'
        }
    }

    It 'rejects invalid metadata shapes' {
        $wfPath = Join-Path -Path $TestDrive -ChildPath 'joiner-invalid.psd1'

        Set-Content -Path $wfPath -Encoding UTF8 -Value @'
@{
  Name           = 'Joiner - Invalid Metadata'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'Test step'
      Type = 'Custom.Step.Test'
    }
  )
}
'@

        $req = New-IdleLifecycleRequest -LifecycleEvent 'Joiner'

        $providers = @{
            StepRegistry = @{
                'Custom.Step.Test' = 'Invoke-CustomStep'
            }
            StepMetadata = @{
                'Custom.Step.Test' = 'not-a-hashtable'
            }
        }

        try {
            New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers | Out-Null
            throw 'Expected an exception but none was thrown.'
        }
        catch {
            $_.Exception.Message | Should -Match 'must be a hashtable'
        }
    }

    It 'rejects invalid capability identifiers' {
        $wfPath = Join-Path -Path $TestDrive -ChildPath 'joiner-invalid-cap.psd1'

        Set-Content -Path $wfPath -Encoding UTF8 -Value @'
@{
  Name           = 'Joiner - Invalid Capability'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'Test step'
      Type = 'Custom.Step.Test'
    }
  )
}
'@

        $req = New-IdleLifecycleRequest -LifecycleEvent 'Joiner'

        $providers = @{
            StepRegistry = @{
                'Custom.Step.Test' = 'Invoke-CustomStep'
            }
            StepMetadata = @{
                'Custom.Step.Test' = @{
                    RequiredCapabilities = @('Invalid Capability With Spaces')
                }
            }
        }

        try {
            New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers | Out-Null
            throw 'Expected an exception but none was thrown.'
        }
        catch {
            $_.Exception.Message | Should -Match 'invalid capability'
        }
    }
}

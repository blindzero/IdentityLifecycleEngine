BeforeAll {
    . (Join-Path (Split-Path -Path $PSScriptRoot -Parent) '_testHelpers.ps1')
    Import-IdleTestModule
    
    # Import Mailbox step pack
    $testsRoot = $PSScriptRoot
    $repoRoot = Split-Path -Path $testsRoot -Parent
    $mailboxModulePath = Join-Path -Path $repoRoot -ChildPath 'src/IdLE.Steps.Mailbox/IdLE.Steps.Mailbox.psd1'
    if (Test-Path -LiteralPath $mailboxModulePath -PathType Leaf) {
        Import-Module $mailboxModulePath -Force -ErrorAction Stop
    }
}

AfterAll {
    Remove-Module -Name 'IdLE.Steps.Mailbox' -ErrorAction SilentlyContinue
}

Describe 'Invoke-IdlePlan - Mailbox step alias resolution' {
    
    BeforeEach {
        # Create mock ExchangeOnline provider
        $script:Provider = [pscustomobject]@{
            PSTypeName = 'Mock.ExchangeOnlineProvider'
            Store      = @{}
        }
        
        $script:Provider | Add-Member -MemberType ScriptMethod -Name GetCapabilities -Value {
            return @('IdLE.Mailbox.Info.Read', 'IdLE.Mailbox.OutOfOffice.Ensure')
        } -Force
        
        $script:Provider | Add-Member -MemberType ScriptMethod -Name EnsureOutOfOffice -Value {
            param($IdentityKey, $Config, $AuthSession)
            
            if (-not $this.Store.ContainsKey($IdentityKey)) {
                $this.Store[$IdentityKey] = @{
                    OOFMode = 'Disabled'
                }
            }
            
            $mailbox = $this.Store[$IdentityKey]
            $changed = ($mailbox['OOFMode'] -ne $Config['Mode'])
            
            if ($changed) {
                $mailbox['OOFMode'] = $Config['Mode']
                $mailbox['OOFInternalMessage'] = if ($Config.ContainsKey('InternalMessage')) { $Config['InternalMessage'] } else { '' }
                $mailbox['OOFExternalMessage'] = if ($Config.ContainsKey('ExternalMessage')) { $Config['ExternalMessage'] } else { '' }
            }
            
            return [pscustomobject]@{
                PSTypeName  = 'IdLE.ProviderResult'
                Operation   = 'EnsureOutOfOffice'
                IdentityKey = $IdentityKey
                Changed     = $changed
            }
        } -Force
        
        # Create mock AuthSessionBroker
        $script:AuthBroker = New-IdleAuthSessionBroker `
            -AuthSessionType 'OAuth' `
            -DefaultAuthSession ([pscustomobject]@{ Token = 'mock-token' })
    }
    
    It 'resolves canonical step type IdLE.Step.Mailbox.OutOfOffice.Ensure' {
        $wfPath = Join-Path -Path $TestDrive -ChildPath 'mailbox-oof-canonical.psd1'
        Set-Content -Path $wfPath -Encoding UTF8 -Value @'
@{
  Name           = 'OOF Canonical'
  LifecycleEvent = 'Leaver'
  Steps          = @(
    @{
      Name = 'SetOOF'
      Type = 'IdLE.Step.Mailbox.OutOfOffice.Ensure'
      With = @{
        Provider    = 'ExchangeOnline'
        IdentityKey = 'user@contoso.com'
        Config      = @{
          Mode            = 'Enabled'
          InternalMessage = 'Out of office.'
          ExternalMessage = 'Out of office.'
        }
      }
    }
  )
}
'@

        $req = New-IdleLifecycleRequest -LifecycleEvent 'Leaver'
        $providers = @{
            ExchangeOnline    = $script:Provider
            AuthSessionBroker = $script:AuthBroker
        }

        $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers
        $plan | Should -Not -BeNullOrEmpty
        $plan.Steps.Count | Should -Be 1
        $plan.Steps[0].Type | Should -Be 'IdLE.Step.Mailbox.OutOfOffice.Ensure'
        
        $result = Invoke-IdlePlan -Plan $plan -Providers $providers
        
        # Debug: show error if failed
        if ($result.Status -ne 'Completed') {
            Write-Host "Plan execution failed. Step error: $($result.Steps[0].Error)"
        }
        
        $result.Status | Should -Be 'Completed'
        $result.Steps[0].Status | Should -Be 'Completed'
    }
    
    It 'resolves alias step type IdLE.Step.Mailbox.EnsureOutOfOffice to same handler' {
        $wfPath = Join-Path -Path $TestDrive -ChildPath 'mailbox-oof-alias.psd1'
        Set-Content -Path $wfPath -Encoding UTF8 -Value @'
@{
  Name           = 'OOF Alias'
  LifecycleEvent = 'Leaver'
  Steps          = @(
    @{
      Name = 'SetOOF'
      Type = 'IdLE.Step.Mailbox.EnsureOutOfOffice'
      With = @{
        Provider    = 'ExchangeOnline'
        IdentityKey = 'user@contoso.com'
        Config      = @{
          Mode            = 'Enabled'
          InternalMessage = 'Out of office.'
          ExternalMessage = 'Out of office.'
        }
      }
    }
  )
}
'@

        $req = New-IdleLifecycleRequest -LifecycleEvent 'Leaver'
        $providers = @{
            ExchangeOnline    = $script:Provider
            AuthSessionBroker = $script:AuthBroker
        }

        $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers
        $plan | Should -Not -BeNullOrEmpty
        $plan.Steps.Count | Should -Be 1
        $plan.Steps[0].Type | Should -Be 'IdLE.Step.Mailbox.EnsureOutOfOffice'
        
        $result = Invoke-IdlePlan -Plan $plan -Providers $providers
        $result.Status | Should -Be 'Completed'
        $result.Steps[0].Status | Should -Be 'Completed'
    }
    
    It 'alias derives same capabilities as canonical type' {
        $wfPathCanonical = Join-Path -Path $TestDrive -ChildPath 'mailbox-canonical.psd1'
        Set-Content -Path $wfPathCanonical -Encoding UTF8 -Value @'
@{
  Name           = 'Canonical'
  LifecycleEvent = 'Leaver'
  Steps          = @(
    @{ Name = 'Step1'; Type = 'IdLE.Step.Mailbox.OutOfOffice.Ensure'; With = @{ Provider = 'ExchangeOnline'; IdentityKey = 'user@contoso.com'; Config = @{ Mode = 'Enabled' } } }
  )
}
'@

        $wfPathAlias = Join-Path -Path $TestDrive -ChildPath 'mailbox-alias.psd1'
        Set-Content -Path $wfPathAlias -Encoding UTF8 -Value @'
@{
  Name           = 'Alias'
  LifecycleEvent = 'Leaver'
  Steps          = @(
    @{ Name = 'Step1'; Type = 'IdLE.Step.Mailbox.EnsureOutOfOffice'; With = @{ Provider = 'ExchangeOnline'; IdentityKey = 'user@contoso.com'; Config = @{ Mode = 'Enabled' } } }
  )
}
'@

        $req = New-IdleLifecycleRequest -LifecycleEvent 'Leaver'
        $providers = @{
            ExchangeOnline    = $script:Provider
            AuthSessionBroker = $script:AuthBroker
        }

        $planCanonical = New-IdlePlan -WorkflowPath $wfPathCanonical -Request $req -Providers $providers
        $planAlias = New-IdlePlan -WorkflowPath $wfPathAlias -Request $req -Providers $providers
        
        $planCanonical.Steps[0].RequiresCapabilities | Should -Be $planAlias.Steps[0].RequiresCapabilities
    }
}

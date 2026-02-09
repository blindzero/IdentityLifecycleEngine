Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

BeforeAll {
    . (Join-Path (Split-Path -Path $PSScriptRoot -Parent) '_testHelpers.ps1')
    Import-IdleTestModule
    Import-IdleTestMailboxModule

}

AfterAll {
    Remove-Module -Name 'IdLE.Steps.Mailbox' -ErrorAction SilentlyContinue
}

Describe 'Mailbox OutOfOffice step - template resolution' {
    
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
                    OOFMode            = 'Disabled'
                    OOFInternalMessage = ''
                    OOFExternalMessage = ''
                }
            }
            
            $mailbox = $this.Store[$IdentityKey]
            
            # Store the config for test validation
            $mailbox['OOFMode'] = $Config['Mode']
            $mailbox['OOFInternalMessage'] = if ($Config.ContainsKey('InternalMessage')) { $Config['InternalMessage'] } else { '' }
            $mailbox['OOFExternalMessage'] = if ($Config.ContainsKey('ExternalMessage')) { $Config['ExternalMessage'] } else { '' }
            $mailbox['OOFExternalAudience'] = if ($Config.ContainsKey('ExternalAudience')) { $Config['ExternalAudience'] } else { '' }
            
            return [pscustomobject]@{
                PSTypeName  = 'IdLE.ProviderResult'
                Operation   = 'EnsureOutOfOffice'
                IdentityKey = $IdentityKey
                Changed     = $true
            }
        } -Force
        
        # Create mock AuthSessionBroker
        $script:AuthBroker = New-IdleAuthSessionBroker `
            -AuthSessionType 'OAuth' `
            -DefaultAuthSession 'mock-token-string'
    }
    
    It 'resolves template variables in InternalMessage and ExternalMessage' {
        $wfPath = Join-Path -Path $TestDrive -ChildPath 'oof-with-templates.psd1'
        Set-Content -Path $wfPath -Encoding UTF8 -Value @'
@{
  Name           = 'OOF with Templates'
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
          InternalMessage = 'Please contact {{Request.DesiredState.Manager.DisplayName}} at {{Request.DesiredState.Manager.Mail}}.'
          ExternalMessage = 'Please contact {{Request.DesiredState.Manager.Mail}}.'
          ExternalAudience = 'All'
        }
      }
    }
  )
}
'@

        $req = New-IdleLifecycleRequest `
            -LifecycleEvent 'Leaver' `
            -Actor 'admin@contoso.com' `
            -DesiredState @{
                Manager = @{
                    DisplayName = 'Jane Smith'
                    Mail        = 'jane.smith@contoso.com'
                }
            }
        
        # Plan creation doesn't need providers with brokers (they contain ScriptBlocks)
        # Pass providers only to Invoke-IdlePlan
        $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers @{
            ExchangeOnline = $script:Provider
        }
        $plan | Should -Not -BeNullOrEmpty
        
        # Verify templates were resolved in the plan
        $plan.Steps[0].With.Config.InternalMessage | Should -Be 'Please contact Jane Smith at jane.smith@contoso.com.'
        $plan.Steps[0].With.Config.ExternalMessage | Should -Be 'Please contact jane.smith@contoso.com.'
        
        # Execute and verify provider received resolved values
        # AuthSessionBroker is passed here for execution
        $providers = @{
            ExchangeOnline    = $script:Provider
            AuthSessionBroker = $script:AuthBroker
        }
        $result = Invoke-IdlePlan -Plan $plan -Providers $providers
        $result.Status | Should -Be 'Completed'
        
        $mailbox = $script:Provider.Store['user@contoso.com']
        $mailbox.OOFInternalMessage | Should -Be 'Please contact Jane Smith at jane.smith@contoso.com.'
        $mailbox.OOFExternalMessage | Should -Be 'Please contact jane.smith@contoso.com.'
    }
    
    It 'resolves nested template variables from Request.DesiredState' {
        $wfPath = Join-Path -Path $TestDrive -ChildPath 'oof-nested-templates.psd1'
        Set-Content -Path $wfPath -Encoding UTF8 -Value @'
@{
  Name           = 'OOF with Nested Templates'
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
          InternalMessage = 'User has left. Contact: {{Request.DesiredState.Handover.Name}} ({{Request.DesiredState.Handover.Email}})'
          ExternalMessage = 'For assistance: {{Request.DesiredState.Handover.Email}}'
        }
      }
    }
  )
}
'@

        $req = New-IdleLifecycleRequest `
            -LifecycleEvent 'Leaver' `
            -Actor 'admin@contoso.com' `
            -DesiredState @{
                Handover = @{
                    Name  = 'Bob Johnson'
                    Email = 'bob.johnson@contoso.com'
                }
            }
        
        # Plan creation doesn't need providers with brokers (they contain ScriptBlocks)
        $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers @{
            ExchangeOnline = $script:Provider
        }
        
        $plan.Steps[0].With.Config.InternalMessage | Should -Be 'User has left. Contact: Bob Johnson (bob.johnson@contoso.com)'
        $plan.Steps[0].With.Config.ExternalMessage | Should -Be 'For assistance: bob.johnson@contoso.com'
    }
    
    It 'works with new step type naming and templates' {
        $wfPath = Join-Path -Path $TestDrive -ChildPath 'oof-new-naming-templates.psd1'
        Set-Content -Path $wfPath -Encoding UTF8 -Value @'
@{
  Name           = 'OOF New Naming with Templates'
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
          InternalMessage = 'Contact {{Request.DesiredState.TeamLead.Name}}'
          ExternalMessage = 'Email {{Request.DesiredState.TeamLead.Email}}'
        }
      }
    }
  )
}
'@

        $req = New-IdleLifecycleRequest `
            -LifecycleEvent 'Leaver' `
            -Actor 'admin@contoso.com' `
            -DesiredState @{
                TeamLead = @{
                    Name  = 'Alice Brown'
                    Email = 'alice.brown@contoso.com'
                }
            }
        
        # Plan creation doesn't need providers with brokers (they contain ScriptBlocks)
        $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers @{
            ExchangeOnline = $script:Provider
        }
        $plan.Steps[0].Type | Should -Be 'IdLE.Step.Mailbox.EnsureOutOfOffice'
        $plan.Steps[0].With.Config.InternalMessage | Should -Be 'Contact Alice Brown'
        
        # Execute with full providers including broker
        $providers = @{
            ExchangeOnline    = $script:Provider
            AuthSessionBroker = $script:AuthBroker
        }
        $result = Invoke-IdlePlan -Plan $plan -Providers $providers
        $result.Status | Should -Be 'Completed'
        
        $mailbox = $script:Provider.Store['user@contoso.com']
        $mailbox.OOFInternalMessage | Should -Be 'Contact Alice Brown'
    }
}

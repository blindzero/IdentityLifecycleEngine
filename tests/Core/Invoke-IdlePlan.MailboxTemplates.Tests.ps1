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
    Context 'Template resolution' {
        BeforeEach {
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

            $script:AuthBroker = New-IdleAuthSessionBroker `
                -AuthSessionType 'OAuth' `
                -DefaultAuthSession 'mock-token-string'
        }

        It 'resolves template variables in InternalMessage and ExternalMessage' {
            $wfPath = New-IdleTestWorkflowFile -FileName 'oof-with-templates.psd1' -Content @'
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
          Mode             = 'Enabled'
          InternalMessage  = 'Please contact {{Request.DesiredState.Manager.DisplayName}} at {{Request.DesiredState.Manager.Mail}}.'
          ExternalMessage  = 'Please contact {{Request.DesiredState.Manager.Mail}}.'
          ExternalAudience = 'All'
        }
      }
    }
  )
}
'@

            $req = New-IdleTestRequest `
                -LifecycleEvent 'Leaver' `
                -Actor 'admin@contoso.com' `
                -DesiredState @{
                    Manager = @{
                        DisplayName = 'Jane Smith'
                        Mail        = 'jane.smith@contoso.com'
                    }
                }

            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers @{ ExchangeOnline = $script:Provider }
            $plan | Should -Not -BeNullOrEmpty

            $plan.Steps[0].With.Config.InternalMessage | Should -Be 'Please contact Jane Smith at jane.smith@contoso.com.'
            $plan.Steps[0].With.Config.ExternalMessage | Should -Be 'Please contact jane.smith@contoso.com.'

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
            $wfPath = New-IdleTestWorkflowFile -FileName 'oof-nested-templates.psd1' -Content @'
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

            $req = New-IdleTestRequest `
                -LifecycleEvent 'Leaver' `
                -Actor 'admin@contoso.com' `
                -DesiredState @{
                    Handover = @{
                        Name  = 'Bob Johnson'
                        Email = 'bob.johnson@contoso.com'
                    }
                }

            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers @{ ExchangeOnline = $script:Provider }

            $plan.Steps[0].With.Config.InternalMessage | Should -Be 'User has left. Contact: Bob Johnson (bob.johnson@contoso.com)'
            $plan.Steps[0].With.Config.ExternalMessage | Should -Be 'For assistance: bob.johnson@contoso.com'
        }

        It 'works with new step type naming and templates' {
            $wfPath = New-IdleTestWorkflowFile -FileName 'oof-new-naming-templates.psd1' -Content @'
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

            $req = New-IdleTestRequest `
                -LifecycleEvent 'Leaver' `
                -Actor 'admin@contoso.com' `
                -DesiredState @{
                    TeamLead = @{
                        Name  = 'Alice Brown'
                        Email = 'alice.brown@contoso.com'
                    }
                }

            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers @{ ExchangeOnline = $script:Provider }
            $plan.Steps[0].Type | Should -Be 'IdLE.Step.Mailbox.EnsureOutOfOffice'
            $plan.Steps[0].With.Config.InternalMessage | Should -Be 'Contact Alice Brown'

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
}

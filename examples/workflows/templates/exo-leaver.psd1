@{
    Name           = 'ExchangeOnline Leaver - Mailbox Offboarding'
    LifecycleEvent = 'Leaver'
    Description    = 'Converts mailbox to shared and enables Out of Office with dynamic manager/service-desk contact information.'

    Steps          = @(
        @{
            Name = 'GetMailboxInfo'
            Type = 'IdLE.Step.Mailbox.GetInfo'
            With = @{
                Provider    = 'ExchangeOnline'
                IdentityKey = '{{Request.Input.UserPrincipalName}}'
            }
        }
        @{
            Name = 'ConvertToSharedMailbox'
            Type = 'IdLE.Step.Mailbox.EnsureType'
            With = @{
                Provider    = 'ExchangeOnline'
                IdentityKey = '{{Request.Input.UserPrincipalName}}'
                MailboxType = 'Shared'
            }
        }
        @{
            Name = 'EnableOutOfOfficeWithManagerContact'
            Type = 'IdLE.Step.Mailbox.EnsureOutOfOffice'
            With = @{
                Provider    = 'ExchangeOnline'
                IdentityKey = '{{Request.Input.UserPrincipalName}}'
                Config      = @{
                    Mode             = 'Enabled'
                    MessageFormat    = 'Html'

                    InternalMessage  = @'
<p>This mailbox is no longer monitored.</p>
<p>For urgent matters, please contact:</p>
<ul>
  <li><strong>Manager:</strong> <a href="mailto:{{Request.DesiredState.Manager.Mail}}">{{Request.DesiredState.Manager.DisplayName}}</a></li>
  <li><strong>Service Desk:</strong> <a href="mailto:{{Request.Input.ServiceDesk.Mail}}">{{Request.Input.ServiceDesk.DisplayName}}</a></li>
</ul>
'@

                    ExternalMessage  = @'
<p>This mailbox is no longer monitored.</p>
<p>Please contact our <strong>Service Desk</strong> at <a href="mailto:{{Request.Input.ServiceDesk.Mail}}">{{Request.Input.ServiceDesk.Mail}}</a>.</p>
'@

                    ExternalAudience = 'All'
                }
            }
        }
        @{
            Name = 'EmitCompletionEvent'
            Type = 'IdLE.Step.EmitEvent'
            With = @{
                Message = 'Mailbox offboarding completed for {{Request.Input.UserPrincipalName}}.'
            }
        }
    )
}

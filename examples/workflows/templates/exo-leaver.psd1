@{
    Name           = 'ExchangeOnline Leaver - Mailbox Offboarding'
    LifecycleEvent = 'Leaver'
    Description    = 'Converts a user mailbox to shared and enables Out of Office with dynamic manager/service-desk contact information.'

    Steps          = @(
        @{
            Name = 'GetMailboxInfo'
            Type = 'IdLE.Step.Mailbox.GetInfo'
            With = @{
                Provider    = 'ExchangeOnline'
                IdentityKey = '{{Request.Intent.UserPrincipalName}}'
            }
        }
        # GetMailboxInfo publishes State.GetMailboxInfo.Mailbox for the following steps.
        # Room and equipment mailboxes are left as they are.
        @{
            Name                = 'ConvertToSharedMailbox'
            Type                = 'IdLE.Step.Mailbox.EnsureType'
            Precondition        = @{
                In = @{ Path = 'State.GetMailboxInfo.Mailbox.Type'; Values = @('User', 'Shared') }
            }
            OnPreconditionFalse = 'Continue'
            With                = @{
                Provider    = 'ExchangeOnline'
                IdentityKey = '{{Request.Intent.UserPrincipalName}}'
                MailboxType = 'Shared'
            }
        }
        @{
            Name = 'EnableOutOfOfficeWithManagerContact'
            Type = 'IdLE.Step.Mailbox.EnsureOutOfOffice'
            With = @{
                Provider    = 'ExchangeOnline'
                IdentityKey = '{{Request.Intent.UserPrincipalName}}'
                Config      = @{
                    Mode             = 'Enabled'
                    MessageFormat    = 'Html'

                    InternalMessage  = @'
<p>This mailbox is no longer monitored.</p>
<p>For urgent matters, please contact:</p>
<ul>
  <li><strong>Manager:</strong> <a href="mailto:{{Request.Intent.Manager.Mail}}">{{Request.Intent.Manager.DisplayName}}</a></li>
  <li><strong>Service Desk:</strong> <a href="mailto:{{Request.Intent.ServiceDesk.Mail}}">{{Request.Intent.ServiceDesk.DisplayName}}</a></li>
</ul>
'@

                    ExternalMessage  = @'
<p>This mailbox is no longer monitored.</p>
<p>Please contact our <strong>Service Desk</strong> at <a href="mailto:{{Request.Intent.ServiceDesk.Mail}}">{{Request.Intent.ServiceDesk.Mail}}</a>.</p>
'@

                    ExternalAudience = 'All'
                }
            }
        }
        @{
            Name = 'EmitCompletionEvent'
            Type = 'IdLE.Step.EmitEvent'
            With = @{
                # Resolved when the step runs, after GetMailboxInfo has published its State.
                Message = 'Mailbox offboarding completed for {{Request.Intent.UserPrincipalName}} ({{State.GetMailboxInfo.Mailbox.PrimarySmtpAddress}}).'
            }
        }
    )
}

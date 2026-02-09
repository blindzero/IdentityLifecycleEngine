@{
    Name           = 'ExchangeOnline Leaver - Mailbox Offboarding'
    LifecycleEvent = 'Leaver'
    Description    = 'Converts mailbox to shared, enables Out of Office with dynamic manager contact info, and optionally delegates access for offboarding users.'
    Steps          = @(
        @{
            Name = 'GetMailboxInfo'
            Type = 'IdLE.Step.Mailbox.GetInfo'
            With = @{
                Provider    = 'ExchangeOnline'
                IdentityKey = @{ ValueFrom = 'Request.Input.UserPrincipalName' }
            }
        }
        @{
            Name = 'ConvertToSharedMailbox'
            Type = 'IdLE.Step.Mailbox.EnsureType'
            With = @{
                Provider    = 'ExchangeOnline'
                IdentityKey = @{ ValueFrom = 'Request.Input.UserPrincipalName' }
                MailboxType = 'Shared'
            }
        }
        @{
            Name = 'EnableOutOfOfficeWithManagerContact'
            Type = 'IdLE.Step.Mailbox.EnsureOutOfOffice'
            With = @{
                Provider    = 'ExchangeOnline'
                IdentityKey = @{ ValueFrom = 'Request.Input.UserPrincipalName' }
                Config      = @{
                    Mode            = 'Enabled'
                    InternalMessage = 'This mailbox is no longer monitored. Please contact {{Request.DesiredState.Manager.DisplayName}} ({{Request.DesiredState.Manager.Mail}}).'
                    ExternalMessage = 'This mailbox is no longer monitored. Please contact {{Request.DesiredState.Manager.Mail}}.'
                    ExternalAudience = 'All'
                }
            }
        }
        @{
            Name = 'EmitCompletionEvent'
            Type = 'IdLE.Step.EmitEvent'
            With = @{
                Message = 'Mailbox offboarding completed.'
            }
        }
    )
}

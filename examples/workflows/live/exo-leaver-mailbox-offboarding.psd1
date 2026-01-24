@{
    Name           = 'ExchangeOnline Leaver - Mailbox Offboarding'
    LifecycleEvent = 'Leaver'
    Description    = 'Converts mailbox to shared, enables Out of Office, and optionally delegates access for offboarding users.'
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
            Type = 'IdLE.Step.Mailbox.Type.Ensure'
            With = @{
                Provider    = 'ExchangeOnline'
                IdentityKey = @{ ValueFrom = 'Request.Input.UserPrincipalName' }
                MailboxType = 'Shared'
            }
        }
        @{
            Name = 'EnableOutOfOffice'
            Type = 'IdLE.Step.Mailbox.OutOfOffice.Ensure'
            With = @{
                Provider    = 'ExchangeOnline'
                IdentityKey = @{ ValueFrom = 'Request.Input.UserPrincipalName' }
                Config      = @{
                    Mode            = 'Enabled'
                    InternalMessage = 'This person is no longer with the organization. For assistance, please contact their manager or the main office.'
                    ExternalMessage = 'This person is no longer with the organization. Please contact the main office for assistance.'
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

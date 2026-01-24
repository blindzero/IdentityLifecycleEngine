@{
    Name           = 'ExchangeOnline Leaver - Mailbox Offboarding'
    LifecycleEvent = 'Leaver'
    Description    = 'Converts mailbox to shared, enables Out of Office, and optionally delegates access for offboarding users.'
    Steps          = @(
        @{
            Name = 'ReportMailboxStatus'
            Type = 'IdLE.Step.Mailbox.Report'
            With = @{
                Provider    = 'ExchangeOnline'
                IdentityKey = '{{Request.Input.UserPrincipalName}}'
            }
        }
        @{
            Name = 'ConvertToSharedMailbox'
            Type = 'IdLE.Step.Mailbox.Type.Ensure'
            With = @{
                Provider    = 'ExchangeOnline'
                IdentityKey = '{{Request.Input.UserPrincipalName}}'
                MailboxType = 'Shared'
            }
        }
        @{
            Name = 'EnableOutOfOffice'
            Type = 'IdLE.Step.Mailbox.OutOfOffice.Ensure'
            With = @{
                Provider    = 'ExchangeOnline'
                IdentityKey = '{{Request.Input.UserPrincipalName}}'
                Config      = @{
                    Mode            = 'Enabled'
                    InternalMessage = '{{Request.Input.DisplayName}} is no longer with the organization. For assistance, please contact {{Request.Input.ManagerEmail}}.'
                    ExternalMessage = 'This person is no longer with the organization. Please contact the main office for assistance.'
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

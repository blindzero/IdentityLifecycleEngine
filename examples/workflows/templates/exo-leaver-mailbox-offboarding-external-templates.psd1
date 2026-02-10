@{
    Name           = 'ExchangeOnline Leaver - Mailbox Offboarding (With External Templates)'
    LifecycleEvent = 'Leaver'
    Description    = 'Converts mailbox to shared, enables Out of Office using HTML templates loaded from external files.'
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
            Name = 'EnableOutOfOfficeWithExternalTemplates'
            Type = 'IdLE.Step.Mailbox.EnsureOutOfOffice'
            With = @{
                Provider    = 'ExchangeOnline'
                IdentityKey = @{ ValueFrom = 'Request.Input.UserPrincipalName' }
                Config      = @{
                    Mode            = 'Enabled'
                    MessageFormat   = 'Html'
                    # Load HTML templates from external files
                    # Template files can contain {{...}} placeholders that will be resolved
                    InternalMessage  = @{ FromFile = './templates/oof-leaver-internal.html' }
                    ExternalMessage  = @{ FromFile = './templates/oof-leaver-external.html' }
                    ExternalAudience = 'All'
                }
            }
        }
        @{
            Name = 'EmitCompletionEvent'
            Type = 'IdLE.Step.EmitEvent'
            With = @{
                Message = 'Mailbox offboarding completed with external OOF templates.'
            }
        }
    )
}

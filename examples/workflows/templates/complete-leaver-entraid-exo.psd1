@{
    Name           = 'Complete Leaver - EntraID + ExchangeOnline Offboarding'
    LifecycleEvent = 'Leaver'
    Description    = 'Complete offboarding workflow: disables EntraID account, converts mailbox to shared, and enables Out of Office.'
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
            Name = 'EnableOutOfOffice'
            Type = 'IdLE.Step.Mailbox.EnsureOutOfOffice'
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
            Name = 'RevokeAllGroupMemberships'
            Type = 'IdLE.Step.EnsureEntitlement'
            With = @{
                Provider           = 'Identity'
                AuthSessionName    = 'MicrosoftGraph'
                AuthSessionOptions = @{ Role = 'Admin' }
                IdentityKey        = @{ ValueFrom = 'Request.Input.UserObjectId' }
                Desired            = @()
            }
        }
        @{
            Name = 'ClearManager'
            Type = 'IdLE.Step.EnsureAttribute'
            With = @{
                Provider           = 'Identity'
                AuthSessionName    = 'MicrosoftGraph'
                AuthSessionOptions = @{ Role = 'Admin' }
                IdentityKey        = @{ ValueFrom = 'Request.Input.UserObjectId' }
                Name               = 'Manager'
                Value              = $null
            }
        }
        @{
            Name = 'DisableEntraIDAccount'
            Type = 'IdLE.Step.DisableIdentity'
            With = @{
                Provider           = 'Identity'
                AuthSessionName    = 'MicrosoftGraph'
                AuthSessionOptions = @{ Role = 'Admin' }
                IdentityKey        = @{ ValueFrom = 'Request.Input.UserObjectId' }
            }
        }
        @{
            Name = 'EmitCompletionEvent'
            Type = 'IdLE.Step.EmitEvent'
            With = @{
                Message = 'Complete offboarding finished: Mailbox converted to Shared, OOF enabled, EntraID account disabled.'
            }
        }
    )
}

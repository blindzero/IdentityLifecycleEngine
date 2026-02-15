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
            Name = 'RevokeAllGroupMemberships'
            Type = 'IdLE.Step.EnsureEntitlement'
            With = @{
                Provider           = 'Identity'
                AuthSessionName    = 'MicrosoftGraph'
                AuthSessionOptions = @{ Role = 'Admin' }
                IdentityKey = '{{Request.Input.UserObjectId}}'
                Desired            = @()
            }
        }
        @{
            Name = 'ClearManager'
            Type = 'IdLE.Step.EnsureAttributes'
            With = @{
                Provider           = 'Identity'
                AuthSessionName    = 'MicrosoftGraph'
                AuthSessionOptions = @{ Role = 'Admin' }
                IdentityKey = '{{Request.Input.UserObjectId}}'
                Attributes         = @{
                    Manager = $null
                }
            }
        }
        @{
            Name = 'DisableEntraIDAccount'
            Type = 'IdLE.Step.DisableIdentity'
            With = @{
                Provider           = 'Identity'
                AuthSessionName    = 'MicrosoftGraph'
                AuthSessionOptions = @{ Role = 'Admin' }
                IdentityKey = '{{Request.Input.UserObjectId}}'
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

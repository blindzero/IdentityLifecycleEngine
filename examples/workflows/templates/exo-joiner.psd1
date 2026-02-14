@{
    Name           = 'ExchangeOnline Joiner - Mailbox Baseline'
    LifecycleEvent = 'Joiner'
    Description    = 'Verifies mailbox existence/type and applies a minimal safe baseline (idempotent).'

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
            Name = 'EnsureUserMailboxType'
            Type = 'IdLE.Step.Mailbox.EnsureType'
            With = @{
                Provider    = 'ExchangeOnline'
                IdentityKey = '{{Request.Input.UserPrincipalName}}'
                MailboxType = 'User'
            }
        }
        @{
            Name = 'EmitCompletionEvent'
            Type = 'IdLE.Step.EmitEvent'
            With = @{
                Message = 'Mailbox baseline verified/applied for {{Request.Input.UserPrincipalName}}.'
            }
        }
    )
}

```

### 2) Keep `entraid-exo-leaver.psd1` but update it to the standard placeholder style

This file is a **cross-provider scenario** (Entra ID + EXO). It should remain **link-only** (not embedded in a single provider page), but it should be consistent:

- Replace all `IdentityKey = @{ ValueFrom = 'Request.Input.X' }` with `IdentityKey = '{{Request.Input.X}}'`

Updated full content:

```powershell
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
            Name = 'EnableOutOfOffice'
            Type = 'IdLE.Step.Mailbox.EnsureOutOfOffice'
            With = @{
                Provider    = 'ExchangeOnline'
                IdentityKey = '{{Request.Input.UserPrincipalName}}'
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

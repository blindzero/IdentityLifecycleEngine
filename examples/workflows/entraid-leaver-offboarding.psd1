@{
    Name           = 'EntraID Leaver - Offboarding with Optional Delete'
    LifecycleEvent = 'Leaver'
    Description    = 'Disables user account and optionally deletes (requires AllowDelete provider flag).'
    Steps          = @(
        @{
            Name = 'RevokeAllGroupMemberships'
            Type = 'IdLE.Step.EnsureEntitlement'
            With = @{
                AuthSessionName    = 'MicrosoftGraph'
                AuthSessionOptions = @{ Role = 'Admin' }
                IdentityKey        = '{{Request.Input.UserObjectId}}'
                Desired            = @()
            }
        }
        @{
            Name = 'ClearManager'
            Type = 'IdLE.Step.EnsureAttribute'
            With = @{
                AuthSessionName    = 'MicrosoftGraph'
                AuthSessionOptions = @{ Role = 'Admin' }
                IdentityKey        = '{{Request.Input.UserObjectId}}'
                Name               = 'Manager'
                Value              = $null
            }
        }
        @{
            Name = 'UpdateDisplayNameWithLeaver'
            Type = 'IdLE.Step.EnsureAttribute'
            With = @{
                AuthSessionName    = 'MicrosoftGraph'
                AuthSessionOptions = @{ Role = 'Admin' }
                IdentityKey        = '{{Request.Input.UserObjectId}}'
                Name               = 'DisplayName'
                Value              = '{{Request.Input.DisplayName}} (LEAVER)'
            }
        }
        @{
            Name = 'DisableAccount'
            Type = 'IdLE.Step.DisableIdentity'
            With = @{
                AuthSessionName    = 'MicrosoftGraph'
                AuthSessionOptions = @{ Role = 'Admin' }
                IdentityKey        = '{{Request.Input.UserObjectId}}'
            }
        }
        @{
            Name = 'DeleteAccountAfterRetention'
            Type = 'IdLE.Step.DeleteIdentity'
            Condition = @{
                Type  = 'Expression'
                Value = '{{Request.Input.DeleteAfterDisable}} -eq $true'
            }
            With = @{
                AuthSessionName    = 'MicrosoftGraph'
                AuthSessionOptions = @{ Role = 'Tier0' }
                IdentityKey        = '{{Request.Input.UserObjectId}}'
            }
        }
        @{
            Name = 'EmitCompletionEvent'
            Type = 'IdLE.Step.EmitEvent'
            With = @{
                Message = 'EntraID user {{Request.Input.UserObjectId}} offboarding completed.'
            }
        }
    )
}

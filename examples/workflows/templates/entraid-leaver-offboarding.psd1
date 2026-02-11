@{
    Name           = 'EntraID Leaver - Offboarding with Optional Delete'
    LifecycleEvent = 'Leaver'
    Description    = 'Disables user account, revokes active sessions, and optionally deletes (requires AllowDelete provider flag).'
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
            Name = 'ClearManagerAndUpdateDisplayName'
            Type = 'IdLE.Step.EnsureAttributes'
            With = @{
                AuthSessionName    = 'MicrosoftGraph'
                AuthSessionOptions = @{ Role = 'Admin' }
                IdentityKey        = '{{Request.Input.UserObjectId}}'
                Attributes         = @{
                    Manager     = $null
                    DisplayName = '{{Request.Input.DisplayName}} (LEAVER)'
                }
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
            Name = 'RevokeActiveSessions'
            Type = 'IdLE.Step.RevokeIdentitySessions'
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
                All = @(
                    @{
                        Equals = @{
                            Path  = 'Request.Input.DeleteAfterDisable'
                            Value = $true
                        }
                    }
                )
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

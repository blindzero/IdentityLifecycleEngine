@{
    Name           = 'EntraID Leaver - Offboarding (Optional Cleanup)'
    LifecycleEvent = 'Leaver'
    Description    = 'Disables the user, revokes active sessions, and performs optional cleanup (group revoke and delete).'

    Steps          = @(
        @{
            Name = 'DisableAccount'
            Type = 'IdLE.Step.DisableIdentity'
            With = @{
                AuthSessionName    = 'MicrosoftGraph'
                AuthSessionOptions = @{ Role = 'Admin' }

                # Prefer ObjectId for leaver (stable), but you may also use UPN if your provider supports it.
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
            Name = 'StampOffboardingMarker'
            Type = 'IdLE.Step.EnsureAttributes'
            With = @{
                AuthSessionName    = 'MicrosoftGraph'
                AuthSessionOptions = @{ Role = 'Admin' }
                IdentityKey        = '{{Request.Input.UserObjectId}}'
                Attributes         = @{
                    DisplayName = '{{Request.Input.DisplayName}} (LEAVER)'
                    Manager     = $null
                }
            }
        }

        # Optional & potentially disruptive:
        # Setting Desired = @() will remove *all* group memberships the provider manages.
        @{
            Name      = 'RevokeAllGroupMemberships_Optional'
            Type      = 'IdLE.Step.EnsureEntitlement'
            Condition = @{
                All = @(
                    @{
                        Equals = @{
                            Path  = 'Request.Input.RevokeAllGroupMemberships'
                            Value = $true
                        }
                    }
                )
            }
            With = @{
                AuthSessionName    = 'MicrosoftGraph'
                AuthSessionOptions = @{ Role = 'Admin' }
                IdentityKey        = '{{Request.Input.UserObjectId}}'
                Desired            = @()
            }
        }

        # Optional delete (requires provider to be created with -AllowDelete)
        @{
            Name      = 'DeleteAccount_Optional'
            Type      = 'IdLE.Step.DeleteIdentity'
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

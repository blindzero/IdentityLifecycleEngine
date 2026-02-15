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
                IdentityKey        = '{{Request.Input.UserPrincipalName}}'
            }
        }

        @{
            Name = 'RevokeActiveSessions'
            Type = 'IdLE.Step.RevokeIdentitySessions'
            With = @{
                AuthSessionName    = 'MicrosoftGraph'
                AuthSessionOptions = @{ Role = 'Admin' }
                IdentityKey        = '{{Request.Input.UserPrincipalName}}'
            }
        }

        @{
            Name = 'StampOffboardingMarker'
            Type = 'IdLE.Step.EnsureAttributes'
            With = @{
                AuthSessionName    = 'MicrosoftGraph'
                AuthSessionOptions = @{ Role = 'Admin' }
                IdentityKey        = '{{Request.Input.UserPrincipalName}}'
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
                IdentityKey        = '{{Request.Input.UserPrincipalName}}'
                Entitlement        = @{
                    Kind = 'Group';
                    Id = '*'
                }
                State = 'Absent'
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
                IdentityKey        = '{{Request.Input.UserPrincipalName}}'
            }
        }

        @{
            Name = 'EmitCompletionEvent'
            Type = 'IdLE.Step.EmitEvent'
            With = @{
                Message = 'EntraID user {{Request.Input.UserPrincipalName}} offboarding completed.'
            }
        }
    )
}

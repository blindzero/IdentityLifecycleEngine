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
                IdentityKey        = '{{Request.Intent.UserPrincipalName}}'
            }
        }

        @{
            Name = 'RevokeActiveSessions'
            Type = 'IdLE.Step.RevokeIdentitySessions'
            With = @{
                AuthSessionName    = 'MicrosoftGraph'
                AuthSessionOptions = @{ Role = 'Admin' }
                IdentityKey        = '{{Request.Intent.UserPrincipalName}}'
            }
        }

        @{
            Name = 'StampOffboardingMarker'
            Type = 'IdLE.Step.EnsureAttributes'
            With = @{
                AuthSessionName    = 'MicrosoftGraph'
                AuthSessionOptions = @{ Role = 'Admin' }
                IdentityKey        = '{{Request.Intent.UserPrincipalName}}'
                Attributes         = @{
                    DisplayName = '{{Request.Intent.DisplayName}} (LEAVER)'
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
                            Path  = 'Request.Intent.RevokeAllGroupMemberships'
                            Value = $true
                        }
                    }
                )
            }
            With = @{
                AuthSessionName    = 'MicrosoftGraph'
                AuthSessionOptions = @{ Role = 'Admin' }
                IdentityKey        = '{{Request.Intent.UserPrincipalName}}'
                Entitlement        = @{
                    Kind = 'Group';
                    Id = '*'
                }
                State = 'Absent'
            }
        }

        # Optional & potentially disruptive:
        # PruneEntitlementsEnsureKeep removes all groups except the keep set AND ensures
        # explicit Keep items are present. Use PruneEntitlements if you only need removal.
        @{
            Name      = 'PruneGroupMemberships_Optional'
            Type      = 'IdLE.Step.PruneEntitlementsEnsureKeep'
            Condition = @{
                All = @(
                    @{
                        Equals = @{
                            Path  = 'Request.Intent.PruneGroupMemberships'
                            Value = $true
                        }
                    }
                )
            }
            With = @{
                AuthSessionName    = 'MicrosoftGraph'
                AuthSessionOptions = @{ Role = 'Admin' }
                IdentityKey        = '{{Request.Intent.UserPrincipalName}}'
                Kind               = 'Group'

                # Retain this specific leaver group and ensure it is present.
                Keep               = @(
                    @{ Kind = 'Group'; Id = '{{Request.Intent.LeaverRetainGroupId}}'; DisplayName = 'Leaver Retain' }
                )

                # Also retain any group whose displayName starts with LEAVER-.
                KeepPattern        = @('LEAVER-*')
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
                            Path  = 'Request.Intent.DeleteAfterDisable'
                            Value = $true
                        }
                    }
                )
            }
            With = @{
                AuthSessionName    = 'MicrosoftGraph'
                AuthSessionOptions = @{ Role = 'Tier0' }
                IdentityKey        = '{{Request.Intent.UserPrincipalName}}'
            }
        }

        @{
            Name = 'EmitCompletionEvent'
            Type = 'IdLE.Step.EmitEvent'
            With = @{
                Message = 'EntraID user {{Request.Intent.UserPrincipalName}} offboarding completed.'
            }
        }
    )
}

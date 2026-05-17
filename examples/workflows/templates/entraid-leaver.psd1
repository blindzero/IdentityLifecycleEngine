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
                IdentityKey        = '{{Request.IdentityKeys.UserPrincipalName}}'
            }
        }

        @{
            Name = 'RevokeActiveSessions'
            Type = 'IdLE.Step.RevokeIdentitySessions'
            With = @{
                AuthSessionName    = 'MicrosoftGraph'
                AuthSessionOptions = @{ Role = 'Admin' }
                IdentityKey        = '{{Request.IdentityKeys.UserPrincipalName}}'
            }
        }

        @{
            Name = 'StampOffboardingMarker'
            Type = 'IdLE.Step.EnsureAttributes'
            With = @{
                AuthSessionName    = 'MicrosoftGraph'
                AuthSessionOptions = @{ Role = 'Admin' }
                IdentityKey        = '{{Request.IdentityKeys.UserPrincipalName}}'
                Attributes         = @{
                    DisplayName = '{{Request.Intent.DisplayName}} (LEAVER)'
                    Manager     = $null
                }
            }
        }

        # Optional: remove ALL group memberships — use when no specific groups need to be retained.
        # PruneEntitlements with an empty Keep list removes every group the provider sees.
        @{
            Name      = 'RevokeAllGroupMemberships_Optional'
            Type      = 'IdLE.Step.PruneEntitlements'
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
                IdentityKey        = '{{Request.IdentityKeys.UserPrincipalName}}'
                Kind               = 'Group'
                Keep               = @()
            }
        }

        # Optional: remove all groups EXCEPT a retain set AND ensure retain set is present.
        # PruneEntitlementsEnsureKeep removes all groups except the keep set AND ensures
        # explicit Keep items are present. Use PruneEntitlements (above) if you only need removal.
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
                IdentityKey        = '{{Request.IdentityKeys.UserPrincipalName}}'
                Kind               = 'Group'

                # Retain this specific leaver group and ensure it is present.
                Keep               = @(
                    @{ Kind = 'Group'; Id = '{{Request.Intent.LeaverRetainGroupId}}' }
                )
                # Pattern-based retention is not supported by PruneEntitlementsEnsureKeep. Use a
                # separate IdLE.Step.PruneEntitlements step earlier if you must protect wildcard
                # matches without granting them.
            }
        }

        # Optional: remove the user from all Administrative Units.
        # Use when scoped admin visibility must be revoked as part of offboarding.
        # This is remove-only: no AU is added. Existing memberships NOT in Keep are removed;
        # Keep entries are protected but NOT granted if missing.
        # Use PruneAdministrativeUnitMemberships_Optional (below) when you also need to guarantee
        # a specific AU is present after the prune.
        @{
            Name      = 'RevokeAdministrativeUnitMemberships_Optional'
            Type      = 'IdLE.Step.PruneEntitlements'
            Condition = @{
                All = @(
                    @{
                        Equals = @{
                            Path  = 'Request.Intent.RevokeAdministrativeUnitMemberships'
                            Value = $true
                        }
                    }
                )
            }
            With = @{
                AuthSessionName    = 'MicrosoftGraph'
                AuthSessionOptions = @{ Role = 'Admin' }
                IdentityKey        = '{{Request.IdentityKeys.UserPrincipalName}}'
                Kind               = 'AdministrativeUnit'
                Keep               = @()
            }
        }

        # Optional: remove all AU memberships EXCEPT a retain set AND ensure retain set is present.
        # PruneEntitlementsEnsureKeep removes all AU memberships except the keep set AND grants
        # any Keep AU that is not currently assigned.
        # Use PruneEntitlements (above) if you only need removal with no guaranteed grant.
        @{
            Name      = 'PruneAdministrativeUnitMemberships_Optional'
            Type      = 'IdLE.Step.PruneEntitlementsEnsureKeep'
            Condition = @{
                All = @(
                    @{
                        Equals = @{
                            Path  = 'Request.Intent.PruneAdministrativeUnitMemberships'
                            Value = $true
                        }
                    }
                )
            }
            With = @{
                AuthSessionName    = 'MicrosoftGraph'
                AuthSessionOptions = @{ Role = 'Admin' }
                IdentityKey        = '{{Request.IdentityKeys.UserPrincipalName}}'
                Kind               = 'AdministrativeUnit'

                # This AU is retained AND guaranteed to be present after the step.
                # Reference by objectId (GUID) or by displayName (must be tenant-unique).
                Keep               = @(
                    @{ Kind = 'AdministrativeUnit'; Id = '{{Request.Intent.RetainAdministrativeUnitId}}' }
                )
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
                IdentityKey        = '{{Request.IdentityKeys.UserPrincipalName}}'
            }
        }

        @{
            Name = 'EmitCompletionEvent'
            Type = 'IdLE.Step.EmitEvent'
            With = @{
                Message = 'EntraID user {{Request.IdentityKeys.UserPrincipalName}} offboarding completed.'
            }
        }
    )
}


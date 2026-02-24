@{
    Name        = 'AD - Leaver (offboarding)'
    LifecycleEvent = 'Leaver'
    Description = 'Disables an AD identity and applies offboarding changes. Includes notes for mover-to-leaver transitions.'

    Steps = @(
        @{
            Type = 'IdLE.Step.DisableIdentity'
            Name     = 'Disable identity'
            With     = @{
                AuthSessionName = 'Directory'
                IdentityKey     = '{{Request.Intent.SamAccountName}}'
                Reason          = '{{Request.Intent.LeaverReason}}'
            }
        }

        @{
            Type = 'IdLE.Step.EnsureAttributes'
            Name     = 'Stamp offboarding attributes'
            With     = @{
                AuthSessionName = 'Directory'
                IdentityKey = '{{Request.Intent.SamAccountName}}'
                Attributes      = @{
                    Description = 'Leaver (CorrelationId: {{Request.CorrelationId}}) - {{Request.Intent.LeaverReason}}'
                }
            }
        }

        # Optional, use with caution:
        # Removing groups can break business processes unexpectedly.
        # PruneEntitlements offers a safer "remove all except" approach for leavers.
        @{
            Type = 'IdLE.Step.PruneEntitlements'
            Name     = 'Prune all group memberships except leaver retain group'
            With     = @{
                Condition       = @{ Equals = @{ Path = 'Request.Intent.PruneGroups'; Value = $true } }
                AuthSessionName = 'Directory'
                IdentityKey     = '{{Request.Intent.SamAccountName}}'
                Kind            = 'Group'

                # Explicitly retain this group and ensure it is present after pruning.
                Keep            = @(
                    @{ Kind = 'Group'; Id = '{{Request.Intent.LeaverRetainGroupDn}}'; DisplayName = 'Leaver Retain' }
                )

                # Also retain any group whose DN starts with CN=LEAVER- (e.g. LEAVER-*)
                KeepPattern     = @('CN=LEAVER-*,OU=Groups,DC=contoso,DC=com')

                # Ensure the explicit keep group is present even if the user was not a member.
                EnsureKeepEntitlements = $true
            }
        }

        # Alternatively, remove individual managed group memberships one by one:
        # Prefer PruneEntitlements above for bulk removal scenarios.
        @{
            Type = 'IdLE.Step.EnsureEntitlement'
            Name     = 'Remove managed group memberships (optional, item 1)'
            With     = @{
                Condition       = @{ Equals = @{ Path = 'Request.Intent.RemoveGroups'; Value = $true } }
                AuthSessionName = 'Directory'
                IdentityKey     = '{{Request.Intent.SamAccountName}}'

                # Only remove what you explicitly manage via IdLE.
                Entitlement = @{
                    Kind = 'Group';
                    Id = '{{Request.Intent.ManagedGroupsToRemove.0}}'
                }
                State = 'Absent'
            }
        }
        @{
            Type = 'IdLE.Step.EnsureEntitlement'
            Name     = 'Remove managed group memberships (optional, item 2)'
            With     = @{
                Condition       = @{ Equals = @{ Path = 'Request.Intent.RemoveGroups'; Value = $true } }
                AuthSessionName = 'Directory'
                IdentityKey = '{{Request.Intent.SamAccountName}}'

                # Only remove what you explicitly manage via IdLE.
                Entitlement = @{
                    Kind = 'Group';
                    Id = '{{Request.Intent.ManagedGroupsToRemove.1}}'
                }
                State = 'Absent'
            }
        }

        # --- Mover-to-leaver transition notes (operational) ---
        # Common approach:
        # - Day 0: Disable + stamp description (safe, minimal risk)
        # - Day N: Remove managed groups + move to Disabled OU (explicit opt-in)
        @{
            Type = 'IdLE.Step.MoveIdentity'
            Name     = 'Move to Disabled OU (optional)'
            With     = @{
                Condition       = @{ Equals = @{ Path = 'Request.Intent.MoveToDisabledOu'; Value = $true } }
                AuthSessionName = 'Directory'
                IdentityKey     = '{{Request.Intent.SamAccountName}}'
                TargetContainer = '{{Request.Intent.DisabledOuPath}}'
            }
        }
    )
}
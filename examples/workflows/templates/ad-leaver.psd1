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
                IdentityKey     = '{{Request.Input.SamAccountName}}'
                Reason          = '{{Request.Input.LeaverReason}}'
            }
        }

        @{
            Type = 'IdLE.Step.EnsureAttributes'
            Name     = 'Stamp offboarding attributes'
            With     = @{
                AuthSessionName = 'Directory'
                IdentityKey = '{{Request.Input.SamAccountName}}'
                Attributes      = @{
                    Description = 'Leaver (CorrelationId: {{Request.CorrelationId}}) - {{Request.Input.LeaverReason}}'
                }
            }
        }

        # Optional, use with caution:
        # Removing groups can break business processes unexpectedly.
        # Prefer an explicit allow-list or a "remove only managed groups" approach.
        @{
            Type = 'IdLE.Step.EnsureEntitlement'
            Name     = 'Remove managed group memberships (optional, item 1)'
            With     = @{
                Condition       = @{ Equals = @{ Path = 'Request.Input.RemoveGroups'; Value = $true } }
                AuthSessionName = 'Directory'
                IdentityKey     = '{{Request.Input.SamAccountName}}'

                # Only remove what you explicitly manage via IdLE.
                Entitlement = @{
                    Kind = 'Group';
                    Id = '{{Request.Input.ManagedGroupsToRemove.0}}'
                }
                State = 'Absent'
            }
        }
        @{
            Type = 'IdLE.Step.EnsureEntitlement'
            Name     = 'Remove managed group memberships (optional, item 2)'
            With     = @{
                Condition       = @{ Equals = @{ Path = 'Request.Input.RemoveGroups'; Value = $true } }
                AuthSessionName = 'Directory'
                IdentityKey = '{{Request.Input.SamAccountName}}'

                # Only remove what you explicitly manage via IdLE.
                Entitlement = @{
                    Kind = 'Group';
                    Id = '{{Request.Input.ManagedGroupsToRemove.1}}'
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
                Condition       = @{ Equals = @{ Path = 'Request.Input.MoveToDisabledOu'; Value = $true } }
                AuthSessionName = 'Directory'
                IdentityKey     = '{{Request.Input.SamAccountName}}'
                TargetContainer = '{{Request.Input.DisabledOuPath}}'
            }
        }
    )
}
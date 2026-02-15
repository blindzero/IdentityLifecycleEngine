@{
    Name        = 'AD - Leaver (offboarding)'
    Description = 'Disables an AD identity and applies offboarding changes. Includes notes for mover-to-leaver transitions.'

    Steps = @(
        @{
            StepType = 'IdLE.Step.DisableIdentity'
            Name     = 'Disable identity'
            With     = @{
                AuthSessionName = '{{Request.Auth.Directory}}'
                Identity        = @{ SamAccountName = '{{Request.Input.SamAccountName}}' }
                Reason          = '{{Request.Input.LeaverReason}}'
            }
        }

        @{
            StepType = 'IdLE.Step.EnsureAttributes'
            Name     = 'Stamp offboarding attributes'
            With     = @{
                AuthSessionName = '{{Request.Auth.Directory}}'
                Identity        = @{ SamAccountName = '{{Request.Input.SamAccountName}}' }
                Attributes      = @{
                    Description = 'Leaver on {{Request.Execution.Timestamp}} - {{Request.Input.LeaverReason}}'
                }
            }
        }

        # Optional, use with caution:
        # Removing groups can break business processes unexpectedly.
        # Prefer an explicit allow-list or a "remove only managed groups" approach.
        @{
            StepType = 'IdLE.Step.EnsureEntitlement'
            Name     = 'Remove managed group memberships (optional)'
            With     = @{
                Condition       = '{{Request.Input.RemoveGroups}}'
                AuthSessionName = '{{Request.Auth.Directory}}'
                Identity        = @{ SamAccountName = '{{Request.Input.SamAccountName}}' }

                # Only remove what you explicitly manage via IdLE.
                Entitlements = @(
                    '{{Request.Input.ManagedGroupsToRemove.0}}'
                    '{{Request.Input.ManagedGroupsToRemove.1}}'
                )
            }
        }

        # --- Mover-to-leaver transition notes (operational) ---
        # Common approach:
        # - Day 0: Disable + stamp description (safe, minimal risk)
        # - Day N: Remove managed groups + move to Disabled OU (explicit opt-in)
        @{
            StepType = 'IdLE.Step.MoveIdentity'
            Name     = 'Move to Disabled OU (optional)'
            With     = @{
                Condition       = '{{Request.Input.MoveToDisabledOu}}'
                AuthSessionName = '{{Request.Auth.Directory}}'
                Identity        = @{ SamAccountName = '{{Request.Input.SamAccountName}}' }
                TargetPath      = '{{Request.Input.DisabledOuPath}}'
            }
        }
    )
}
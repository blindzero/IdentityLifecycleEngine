@{
    Name           = 'Leaver - AD Offboarding Workflow'
    LifecycleEvent = 'Leaver'
    Steps          = @(
        @{
            Name = 'Disable user account'
            Type = 'IdLE.Step.DisableIdentity'
            With = @{
                IdentityKey = 'leavinguser@contoso.local'
                # Provider alias references the provider hashtable key set by the host.
                # The alias name is flexible and chosen when injecting providers.
                Provider    = 'Identity'
            }
        },
        @{
            Name = 'Update Description with termination date'
            Type = 'IdLE.Step.EnsureAttributes'
            With = @{
                IdentityKey = 'leavinguser@contoso.local'
                Attributes  = @{
                    Description = 'Terminated 2026-01-18'
                }
                Provider    = 'Identity'
            }
        },
        @{
            Name = 'Move to Leavers OU'
            Type = 'IdLE.Step.MoveIdentity'
            With = @{
                IdentityKey     = 'leavinguser@contoso.local'
                TargetContainer = 'OU=Leavers,OU=Disabled,DC=contoso,DC=local'
                Provider        = 'Identity'
            }
        },
        @{
            Name      = 'Delete user account (opt-in required)'
            Type      = 'IdLE.Step.DeleteIdentity'
            With      = @{
                IdentityKey = 'leavinguser@contoso.local'
                Provider    = 'Identity'
            }
            Condition = @{
                Exists = @{
                    Path = 'Input.AllowDelete'
                }
            }
        }
    )
}

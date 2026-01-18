@{
    Name           = 'Leaver - AD Offboarding Workflow'
    LifecycleEvent = 'Leaver'
    Steps          = @(
        @{
            Name                 = 'Disable user account'
            Type                 = 'IdLE.Step.DisableIdentity'
            With                 = @{
                IdentityKey = 'leavinguser@contoso.local'
                Provider    = 'Identity'
            }
            RequiresCapabilities = @('IdLE.Identity.Disable')
        },
        @{
            Name                 = 'Update Description with termination date'
            Type                 = 'IdLE.Step.EnsureAttribute'
            With                 = @{
                IdentityKey = 'leavinguser@contoso.local'
                Name        = 'Description'
                Value       = 'Terminated 2026-01-18'
                Provider    = 'Identity'
            }
            RequiresCapabilities = @('IdLE.Identity.Attribute.Ensure')
        },
        @{
            Name                 = 'Move to Leavers OU'
            Type                 = 'IdLE.Step.MoveIdentity'
            With                 = @{
                IdentityKey     = 'leavinguser@contoso.local'
                TargetContainer = 'OU=Leavers,OU=Disabled,DC=contoso,DC=local'
                Provider        = 'Identity'
            }
            RequiresCapabilities = @('IdLE.Identity.Move')
        },
        @{
            Name                 = 'Delete user account (opt-in required)'
            Type                 = 'IdLE.Step.DeleteIdentity'
            With                 = @{
                IdentityKey = 'leavinguser@contoso.local'
                Provider    = 'Identity'
            }
            RequiresCapabilities = @('IdLE.Identity.Delete')
            When                 = @{
                Condition = @{
                    Type  = 'Input.PropertyPresent'
                    Value = 'AllowDelete'
                }
            }
        }
    )
}

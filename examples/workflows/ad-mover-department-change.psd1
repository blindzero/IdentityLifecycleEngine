@{
    Name           = 'Mover - AD Department Change Workflow'
    LifecycleEvent = 'Mover'
    Steps          = @(
        @{
            Name                 = 'Update Department'
            Type                 = 'IdLE.Step.EnsureAttribute'
            With                 = @{
                IdentityKey = 'existinguser@contoso.local'
                Name        = 'Department'
                Value       = 'Sales'
                # Provider alias - can be customized when host creates the provider hashtable.
                # Examples: 'Identity', 'SourceAD', 'TargetAD', 'SystemX', etc.
                Provider    = 'Identity'
            }
            RequiresCapabilities = @('IdLE.Identity.Attribute.Ensure')
        },
        @{
            Name                 = 'Update Title'
            Type                 = 'IdLE.Step.EnsureAttribute'
            With                 = @{
                IdentityKey = 'existinguser@contoso.local'
                Name        = 'Title'
                Value       = 'Sales Manager'
                Provider    = 'Identity'
            }
            RequiresCapabilities = @('IdLE.Identity.Attribute.Ensure')
        },
        @{
            Name                 = 'Revoke old IT department group'
            Type                 = 'IdLE.Step.EnsureEntitlement'
            With                 = @{
                IdentityKey = 'existinguser@contoso.local'
                Entitlement = @{
                    Kind        = 'Group'
                    Id          = 'CN=IT-Department,OU=Groups,DC=contoso,DC=local'
                    DisplayName = 'IT Department'
                }
                State       = 'Absent'
                Provider    = 'Identity'
            }
            RequiresCapabilities = @('IdLE.Entitlement.List', 'IdLE.Entitlement.Revoke')
        },
        @{
            Name                 = 'Grant Sales department group'
            Type                 = 'IdLE.Step.EnsureEntitlement'
            With                 = @{
                IdentityKey = 'existinguser@contoso.local'
                Entitlement = @{
                    Kind        = 'Group'
                    Id          = 'CN=Sales-Department,OU=Groups,DC=contoso,DC=local'
                    DisplayName = 'Sales Department'
                }
                State       = 'Present'
                Provider    = 'Identity'
            }
            RequiresCapabilities = @('IdLE.Entitlement.List', 'IdLE.Entitlement.Grant')
        },
        @{
            Name                 = 'Move to Sales OU'
            Type                 = 'IdLE.Step.MoveIdentity'
            With                 = @{
                IdentityKey     = 'existinguser@contoso.local'
                TargetContainer = 'OU=Sales,OU=Users,DC=contoso,DC=local'
                Provider        = 'Identity'
            }
            RequiresCapabilities = @('IdLE.Identity.Move')
        }
    )
}

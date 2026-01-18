@{
    Name           = 'Joiner - AD Complete Workflow'
    LifecycleEvent = 'Joiner'
    Steps          = @(
        @{
            Name                 = 'Create AD user account'
            Type                 = 'IdLE.Step.CreateIdentity'
            With                 = @{
                IdentityKey = 'newuser'
                Attributes  = @{
                    SamAccountName    = 'newuser'
                    UserPrincipalName = 'newuser@contoso.local'
                    GivenName         = 'New'
                    Surname           = 'User'
                    DisplayName       = 'New User'
                    Description       = 'New employee account'
                    Path              = 'OU=Joiners,OU=Users,DC=contoso,DC=local'
                }
                # Provider alias - references the key in the provider hashtable.
                # The host chooses this name when creating the provider hashtable.
                # If omitted, defaults to 'Identity'.
                Provider    = 'Identity'
            }
            RequiresCapabilities = @('IdLE.Identity.Create')
        },
        @{
            Name                 = 'Set Department'
            Type                 = 'IdLE.Step.EnsureAttribute'
            With                 = @{
                IdentityKey = 'newuser@contoso.local'
                Name        = 'Department'
                Value       = 'IT'
                Provider    = 'Identity'
            }
            RequiresCapabilities = @('IdLE.Identity.Attribute.Ensure')
        },
        @{
            Name                 = 'Set Title'
            Type                 = 'IdLE.Step.EnsureAttribute'
            With                 = @{
                IdentityKey = 'newuser@contoso.local'
                Name        = 'Title'
                Value       = 'Software Engineer'
                Provider    = 'Identity'
            }
            RequiresCapabilities = @('IdLE.Identity.Attribute.Ensure')
        },
        @{
            Name                 = 'Grant base access group'
            Type                 = 'IdLE.Step.EnsureEntitlement'
            With                 = @{
                IdentityKey = 'newuser@contoso.local'
                Entitlement = @{
                    Kind        = 'Group'
                    Id          = 'CN=All-Employees,OU=Groups,DC=contoso,DC=local'
                    DisplayName = 'All Employees'
                }
                State       = 'Present'
                Provider    = 'Identity'
            }
            RequiresCapabilities = @('IdLE.Entitlement.List', 'IdLE.Entitlement.Grant')
        },
        @{
            Name                 = 'Grant IT department group'
            Type                 = 'IdLE.Step.EnsureEntitlement'
            With                 = @{
                IdentityKey = 'newuser@contoso.local'
                Entitlement = @{
                    Kind        = 'Group'
                    Id          = 'CN=IT-Department,OU=Groups,DC=contoso,DC=local'
                    DisplayName = 'IT Department'
                }
                State       = 'Present'
                Provider    = 'Identity'
            }
            RequiresCapabilities = @('IdLE.Entitlement.List', 'IdLE.Entitlement.Grant')
        },
        @{
            Name                 = 'Move to active users OU'
            Type                 = 'IdLE.Step.MoveIdentity'
            With                 = @{
                IdentityKey     = 'newuser@contoso.local'
                TargetContainer = 'OU=Active,OU=Users,DC=contoso,DC=local'
                Provider        = 'Identity'
            }
            RequiresCapabilities = @('IdLE.Identity.Move')
        }
    )
}

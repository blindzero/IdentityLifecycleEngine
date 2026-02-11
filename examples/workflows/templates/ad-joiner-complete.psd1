@{
    Name           = 'Joiner - AD Complete Workflow'
    LifecycleEvent = 'Joiner'
    Steps          = @(
        @{
            Name = 'Create AD user account'
            Type = 'IdLE.Step.CreateIdentity'
            With = @{
                IdentityKey = 'newuser'
                Attributes  = @{
                    SamAccountName    = 'newuser'
                    UserPrincipalName = 'newuser@contoso.local'
                    GivenName         = 'New'
                    Surname           = 'User'
                    DisplayName       = 'New User'
                    Description       = 'New employee account'
                    Path              = 'OU=Joiners,OU=Users,DC=contoso,DC=local'
                    OtherAttributes   = @{
                        # Custom LDAP attributes for organization-specific needs
                        employeeType        = 'Employee'
                        extensionAttribute1 = 'EMPL-2024-001'
                        company             = 'Contoso Ltd'
                    }
                }
                # Provider alias - references the key in the provider hashtable.
                # The host chooses this name when creating the provider hashtable.
                # If omitted, defaults to 'Identity'.
                Provider    = 'Identity'
            }
        },
        @{
            Name = 'Set Department and Title'
            Type = 'IdLE.Step.EnsureAttributes'
            With = @{
                IdentityKey = 'newuser@contoso.local'
                Attributes  = @{
                    Department = 'IT'
                    Title      = 'Software Engineer'
                }
                Provider    = 'Identity'
            }
        },
        @{
            Name = 'Grant base access group'
            Type = 'IdLE.Step.EnsureEntitlement'
            With = @{
                IdentityKey = 'newuser@contoso.local'
                Entitlement = @{
                    Kind        = 'Group'
                    Id          = 'CN=All-Employees,OU=Groups,DC=contoso,DC=local'
                    DisplayName = 'All Employees'
                }
                State       = 'Present'
                Provider    = 'Identity'
            }
        },
        @{
            Name = 'Grant IT department group'
            Type = 'IdLE.Step.EnsureEntitlement'
            With = @{
                IdentityKey = 'newuser@contoso.local'
                Entitlement = @{
                    Kind        = 'Group'
                    Id          = 'CN=IT-Department,OU=Groups,DC=contoso,DC=local'
                    DisplayName = 'IT Department'
                }
                State       = 'Present'
                Provider    = 'Identity'
            }
        },
        @{
            Name = 'Move to active users OU'
            Type = 'IdLE.Step.MoveIdentity'
            With = @{
                IdentityKey     = 'newuser@contoso.local'
                TargetContainer = 'OU=Active,OU=Users,DC=contoso,DC=local'
                Provider        = 'Identity'
            }
        }
    )
}

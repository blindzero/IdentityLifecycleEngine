@{
    Name           = 'Mover - AD Department Change Workflow'
    LifecycleEvent = 'Mover'
    Steps          = @(
        @{
            Name = 'Update Department and Title'
            Type = 'IdLE.Step.EnsureAttributes'
            With = @{
                IdentityKey = 'existinguser@contoso.local'
                Attributes  = @{
                    Department = 'Sales'
                    Title      = 'Sales Manager'
                }
                # Provider alias - can be customized when host creates the provider hashtable.
                # Examples: 'Identity', 'SourceAD', 'TargetAD', 'SystemX', etc.
                Provider    = 'Identity'
            }
        },
        @{
            Name = 'Revoke old IT department group'
            Type = 'IdLE.Step.EnsureEntitlement'
            With = @{
                IdentityKey = 'existinguser@contoso.local'
                Entitlement = @{
                    Kind        = 'Group'
                    Id          = 'CN=IT-Department,OU=Groups,DC=contoso,DC=local'
                    DisplayName = 'IT Department'
                }
                State       = 'Absent'
                Provider    = 'Identity'
            }
        },
        @{
            Name = 'Grant Sales department group'
            Type = 'IdLE.Step.EnsureEntitlement'
            With = @{
                IdentityKey = 'existinguser@contoso.local'
                Entitlement = @{
                    Kind        = 'Group'
                    Id          = 'CN=Sales-Department,OU=Groups,DC=contoso,DC=local'
                    DisplayName = 'Sales Department'
                }
                State       = 'Present'
                Provider    = 'Identity'
            }
        },
        @{
            Name = 'Move to Sales OU'
            Type = 'IdLE.Step.MoveIdentity'
            With = @{
                IdentityKey     = 'existinguser@contoso.local'
                TargetContainer = 'OU=Sales,OU=Users,DC=contoso,DC=local'
                Provider        = 'Identity'
            }
        }
    )
}

@{
    Name           = 'EntraID Joiner - Complete Onboarding'
    LifecycleEvent = 'Joiner'
    Description    = 'Creates a new Entra ID user account with attributes and group memberships.'
    Steps          = @(
        @{
            Name = 'CreateEntraIDUser'
            Type = 'IdLE.Step.CreateIdentity'
            With = @{
                AuthSessionName    = 'MicrosoftGraph'
                AuthSessionOptions = @{ Role = 'Admin' }
                Attributes         = @{
                    UserPrincipalName = '{{Request.Input.UserPrincipalName}}'
                    DisplayName       = '{{Request.Input.DisplayName}}'
                    GivenName         = '{{Request.Input.GivenName}}'
                    Surname           = '{{Request.Input.Surname}}'
                    Mail              = '{{Request.Input.Mail}}'
                    Department        = '{{Request.Input.Department}}'
                    JobTitle          = '{{Request.Input.JobTitle}}'
                    OfficeLocation    = '{{Request.Input.OfficeLocation}}'
                    CompanyName       = 'Contoso Ltd'
                    PasswordProfile   = @{
                        forceChangePasswordNextSignIn = $true
                        password                      = '{{Request.Input.TemporaryPassword}}'
                    }
                }
            }
            Outputs = @(
                'State.EntraID.UserObjectId'
            )
        }
        @{
            Name = 'AddToBaseGroups'
            Type = 'IdLE.Step.EnsureEntitlement'
            With = @{
                AuthSessionName    = 'MicrosoftGraph'
                AuthSessionOptions = @{ Role = 'Admin' }
                IdentityKey        = '{{State.EntraID.UserObjectId}}'
                Desired            = @(
                    @{
                        Kind        = 'Group'
                        Id          = 'all-employees-group-id'
                        DisplayName = 'All Employees'
                    }
                    @{
                        Kind        = 'Group'
                        Id          = '{{Request.Input.DepartmentGroupId}}'
                        DisplayName = '{{Request.Input.DepartmentName}}'
                    }
                )
            }
        }
        @{
            Name = 'SetManagerAttribute'
            Type = 'IdLE.Step.EnsureAttribute'
            Condition = @{
                Type  = 'Expression'
                Value = '{{Request.Input.ManagerId}} -ne $null'
            }
            With = @{
                AuthSessionName    = 'MicrosoftGraph'
                AuthSessionOptions = @{ Role = 'Admin' }
                IdentityKey        = '{{State.EntraID.UserObjectId}}'
                Name               = 'Manager'
                Value              = '{{Request.Input.ManagerId}}'
            }
        }
        @{
            Name = 'EnableAccount'
            Type = 'IdLE.Step.EnableIdentity'
            With = @{
                AuthSessionName    = 'MicrosoftGraph'
                AuthSessionOptions = @{ Role = 'Admin' }
                IdentityKey        = '{{State.EntraID.UserObjectId}}'
            }
        }
        @{
            Name = 'EmitCompletionEvent'
            Type = 'IdLE.Step.EmitEvent'
            With = @{
                Message = 'EntraID user {{State.EntraID.UserObjectId}} created and configured successfully.'
            }
        }
    )
}

@{
    Name           = 'EntraID Joiner - Complete Onboarding'
    LifecycleEvent = 'Joiner'
    Description    = 'Creates or updates an Entra ID user with baseline attributes and group memberships. Includes optional mover patterns.'

    Steps          = @(
        @{
            Name = 'CreateEntraIDUser'
            Type = 'IdLE.Step.CreateIdentity'
            With = @{
                AuthSessionName    = 'MicrosoftGraph'
                AuthSessionOptions = @{ Role = 'Admin' }
                
                # Using UPN keeps it human-friendly in templates.
                IdentityKey        = '{{Request.Intent.UserPrincipalName}}'

                Attributes         = @{
                    UserPrincipalName = '{{Request.Intent.UserPrincipalName}}'
                    DisplayName       = '{{Request.Intent.DisplayName}}'
                    GivenName         = '{{Request.Intent.GivenName}}'
                    Surname           = '{{Request.Intent.Surname}}'
                    Mail              = '{{Request.Intent.Mail}}'

                    # Optional org attributes (safe when empty)
                    Department        = '{{Request.Intent.Department}}'
                    JobTitle          = '{{Request.Intent.JobTitle}}'
                    OfficeLocation    = '{{Request.Intent.OfficeLocation}}'
                    CompanyName       = '{{Request.Intent.CompanyName}}'

                    # Password profile is typically relevant for "new user" scenarios.
                    # Your host can generate and provide a temporary password in Request.Intent.
                    PasswordProfile   = @{
                        forceChangePasswordNextSignIn = $true
                        password                      = '{{Request.Intent.TemporaryPassword}}'
                    }
                }
            }
        }

        @{
            Name = 'AddToBaselineGroups'
            Type = 'IdLE.Step.EnsureEntitlement'
            With = @{
                AuthSessionName    = 'MicrosoftGraph'
                AuthSessionOptions = @{ Role = 'Admin' }

                # Using UPN keeps it human-friendly in templates.
                IdentityKey        = '{{Request.Intent.UserPrincipalName}}'

                # Baseline groups should be explicit and driven by request input (no hardcoding).
                Desired            = @(
                    @{
                        Kind        = 'Group'
                        Id          = '{{Request.Intent.AllEmployeesGroupId}}'
                        DisplayName = '{{Request.Intent.AllEmployeesGroupName}}'
                    }
                    @{
                        Kind        = 'Group'
                        Id          = '{{Request.Intent.DepartmentGroupId}}'
                        DisplayName = '{{Request.Intent.DepartmentGroupName}}'
                    }
                )
            }
        }

        @{
            Name = 'EnableAccount'
            Type = 'IdLE.Step.EnableIdentity'
            With = @{
                AuthSessionName    = 'MicrosoftGraph'
                AuthSessionOptions = @{ Role = 'Admin' }
                IdentityKey        = '{{Request.Intent.UserPrincipalName}}'
            }
        }

        # ----------------------------
        # Mover patterns (optional)
        # Enable by setting: Request.Intent.IsMover = $true
        # ----------------------------

        @{
            Name      = 'Mover_UpdateOrgAttributes'
            Type      = 'IdLE.Step.EnsureAttributes'

            Condition = @{
                All = @(
                    @{
                        Equals = @{
                            Path  = 'Request.Intent.IsMover'
                            Value = $true
                        }
                    }
                )
            }
            With = @{
                AuthSessionName    = 'MicrosoftGraph'
                AuthSessionOptions = @{ Role = 'Admin' }
                IdentityKey        = '{{Request.Intent.UserPrincipalName}}'

                Attributes         = @{
                    Department     = '{{Request.Intent.NewDepartment}}'
                    JobTitle        = '{{Request.Intent.NewJobTitle}}'
                    OfficeLocation  = '{{Request.Intent.NewOfficeLocation}}'
                    Manager         = '{{Request.Intent.NewManagerObjectId}}'
                }
            }
        }

        @{
            Name      = 'Mover_AdjustManagedGroups'
            Type      = 'IdLE.Step.EnsureEntitlement'
            Condition = @{
                All = @(
                    @{
                        Equals = @{
                            Path  = 'Request.Intent.IsMover'
                            Value = $true
                        }
                    }
                )
            }
            With = @{
                AuthSessionName    = 'MicrosoftGraph'
                AuthSessionOptions = @{ Role = 'Admin' }
                IdentityKey        = '{{Request.Intent.UserPrincipalName}}'

                # Optional: add department/project groups as part of a move.
                Desired            = @(
                    @{
                        Kind        = 'Group'
                        Id          = '{{Request.Intent.DepartmentGroupId}}'
                        DisplayName = '{{Request.Intent.DepartmentGroupName}}'
                    }
                    @{
                        Kind        = 'Group'
                        Id          = '{{Request.Intent.ProjectGroupId}}'
                        DisplayName = '{{Request.Intent.ProjectGroupName}}'
                    }
                )
            }
        }

        @{
            Name = 'EmitCompletionEvent'
            Type = 'IdLE.Step.EmitEvent'
            With = @{
                Message = 'EntraID user {{Request.Intent.UserPrincipalName}} created/updated successfully.'
            }
        }
    )
}
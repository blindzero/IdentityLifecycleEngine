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

                Attributes         = @{
                    UserPrincipalName = '{{Request.Input.UserPrincipalName}}'
                    DisplayName       = '{{Request.Input.DisplayName}}'
                    GivenName         = '{{Request.Input.GivenName}}'
                    Surname           = '{{Request.Input.Surname}}'
                    Mail              = '{{Request.Input.Mail}}'

                    # Optional org attributes (safe when empty)
                    Department        = '{{Request.Input.Department}}'
                    JobTitle          = '{{Request.Input.JobTitle}}'
                    OfficeLocation    = '{{Request.Input.OfficeLocation}}'
                    CompanyName       = '{{Request.Input.CompanyName}}'

                    # Password profile is typically relevant for "new user" scenarios.
                    # Your host can generate and provide a temporary password in Request.Input.
                    PasswordProfile   = @{
                        forceChangePasswordNextSignIn = $true
                        password                      = '{{Request.Input.TemporaryPassword}}'
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
                IdentityKey        = '{{Request.Input.UserPrincipalName}}'

                # Baseline groups should be explicit and driven by request input (no hardcoding).
                Desired            = @(
                    @{
                        Kind        = 'Group'
                        Id          = '{{Request.Input.AllEmployeesGroupId}}'
                        DisplayName = '{{Request.Input.AllEmployeesGroupName}}'
                    }
                    @{
                        Kind        = 'Group'
                        Id          = '{{Request.Input.DepartmentGroupId}}'
                        DisplayName = '{{Request.Input.DepartmentGroupName}}'
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
                IdentityKey        = '{{Request.Input.UserPrincipalName}}'
            }
        }

        # ----------------------------
        # Mover patterns (optional)
        # Enable by setting: Request.Input.IsMover = $true
        # ----------------------------

        @{
            Name      = 'Mover_UpdateOrgAttributes'
            Type      = 'IdLE.Step.EnsureAttributes'
            Condition = @{
                All = @(
                    @{
                        Equals = @{
                            Path  = 'Request.Input.IsMover'
                            Value = $true
                        }
                    }
                )
            }
            With = @{
                AuthSessionName    = 'MicrosoftGraph'
                AuthSessionOptions = @{ Role = 'Admin' }
                IdentityKey        = '{{Request.Input.UserPrincipalName}}'

                Attributes         = @{
                    Department     = '{{Request.Input.NewDepartment}}'
                    JobTitle        = '{{Request.Input.NewJobTitle}}'
                    OfficeLocation  = '{{Request.Input.NewOfficeLocation}}'
                    Manager         = '{{Request.Input.NewManagerObjectId}}'
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
                            Path  = 'Request.Input.IsMover'
                            Value = $true
                        }
                    }
                )
            }
            With = @{
                AuthSessionName    = 'MicrosoftGraph'
                AuthSessionOptions = @{ Role = 'Admin' }
                IdentityKey        = '{{Request.Input.UserPrincipalName}}'

                # Optional: add department/project groups as part of a move.
                Desired            = @(
                    @{
                        Kind        = 'Group'
                        Id          = '{{Request.Input.DepartmentGroupId}}'
                        DisplayName = '{{Request.Input.DepartmentGroupName}}'
                    }
                    @{
                        Kind        = 'Group'
                        Id          = '{{Request.Input.ProjectGroupId}}'
                        DisplayName = '{{Request.Input.ProjectGroupName}}'
                    }
                )
            }
        }

        @{
            Name = 'EmitCompletionEvent'
            Type = 'IdLE.Step.EmitEvent'
            With = @{
                Message = 'EntraID user {{Request.Input.UserPrincipalName}} created/updated successfully.'
            }
        }
    )
}
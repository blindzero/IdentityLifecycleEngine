@{
    Name           = 'EntraID Joiner - Complete Onboarding'
    LifecycleEvent = 'Joiner'
    Description    = 'Creates or updates an Entra ID user with baseline attributes, group memberships, and Administrative Unit assignments. Includes optional mover patterns.'

    Steps          = @(
        @{
            Name = 'CreateEntraIDUser'
            Type = 'IdLE.Step.CreateIdentity'
            With = @{
                AuthSessionName    = 'MicrosoftGraph'
                AuthSessionOptions = @{ Role = 'Admin' }

                IdentityKey        = '{{Request.IdentityKeys.UserPrincipalName}}'

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

        # Baseline groups: add one EnsureEntitlement step per group.
        @{
            Name = 'AddToAllEmployeesGroup'
            Type = 'IdLE.Step.EnsureEntitlement'
            With = @{
                AuthSessionName    = 'MicrosoftGraph'
                AuthSessionOptions = @{ Role = 'Admin' }
                IdentityKey        = '{{Request.IdentityKeys.UserPrincipalName}}'
                Entitlement        = @{
                    Kind = 'Group'
                    Id   = '{{Request.Intent.AllEmployeesGroupId}}'
                }
                State              = 'Present'
            }
        }

        @{
            Name = 'AddToDepartmentGroup'
            Type = 'IdLE.Step.EnsureEntitlement'
            With = @{
                AuthSessionName    = 'MicrosoftGraph'
                AuthSessionOptions = @{ Role = 'Admin' }
                IdentityKey        = '{{Request.IdentityKeys.UserPrincipalName}}'
                Entitlement        = @{
                    Kind = 'Group'
                    Id   = '{{Request.Intent.DepartmentGroupId}}'
                }
                State              = 'Present'
            }
        }

        # Baseline Administrative Unit: controls which scoped admins can manage this user.
        # AUs can be referenced by their GUID objectId or by displayName (tenant-unique names only).
        @{
            Name = 'AddToDepartmentAdministrativeUnit'
            Type = 'IdLE.Step.EnsureEntitlement'
            With = @{
                AuthSessionName    = 'MicrosoftGraph'
                AuthSessionOptions = @{ Role = 'Admin' }
                IdentityKey        = '{{Request.IdentityKeys.UserPrincipalName}}'
                Entitlement        = @{
                    Kind = 'AdministrativeUnit'
                    Id   = '{{Request.Intent.DepartmentAdministrativeUnitId}}'
                }
                State              = 'Present'
            }
        }

        @{
            Name = 'EnableAccount'
            Type = 'IdLE.Step.EnableIdentity'
            With = @{
                AuthSessionName    = 'MicrosoftGraph'
                AuthSessionOptions = @{ Role = 'Admin' }
                IdentityKey        = '{{Request.IdentityKeys.UserPrincipalName}}'
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
                IdentityKey        = '{{Request.IdentityKeys.UserPrincipalName}}'

                Attributes         = @{
                    Department     = '{{Request.Intent.NewDepartment}}'
                    JobTitle       = '{{Request.Intent.NewJobTitle}}'
                    OfficeLocation = '{{Request.Intent.NewOfficeLocation}}'
                    Manager        = '{{Request.Intent.NewManagerObjectId}}'
                }
            }
        }

        # Add one EnsureEntitlement step per group change required on a mover.
        @{
            Name      = 'Mover_AddToDepartmentGroup'
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
                IdentityKey        = '{{Request.IdentityKeys.UserPrincipalName}}'
                Entitlement        = @{
                    Kind = 'Group'
                    Id   = '{{Request.Intent.DepartmentGroupId}}'
                }
                State              = 'Present'
            }
        }

        @{
            Name      = 'Mover_AddToProjectGroup'
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
                IdentityKey        = '{{Request.IdentityKeys.UserPrincipalName}}'
                Entitlement        = @{
                    Kind = 'Group'
                    Id   = '{{Request.Intent.ProjectGroupId}}'
                }
                State              = 'Present'
            }
        }

        # Reassign to the new department's Administrative Unit on a move.
        @{
            Name      = 'Mover_AddToNewDepartmentAdministrativeUnit'
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
                IdentityKey        = '{{Request.IdentityKeys.UserPrincipalName}}'
                Entitlement        = @{
                    Kind = 'AdministrativeUnit'
                    Id   = '{{Request.Intent.NewDepartmentAdministrativeUnitId}}'
                }
                State              = 'Present'
            }
        }

        @{
            Name = 'EmitCompletionEvent'
            Type = 'IdLE.Step.EmitEvent'
            With = @{
                Message = 'EntraID user {{Request.IdentityKeys.UserPrincipalName}} created/updated successfully.'
            }
        }
    )
}

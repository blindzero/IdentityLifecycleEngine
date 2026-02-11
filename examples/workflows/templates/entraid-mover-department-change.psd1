@{
    Name           = 'EntraID Mover - Department Change'
    LifecycleEvent = 'Mover'
    Description    = 'Updates user attributes and group memberships when user moves to new department.'
    Steps          = @(
        @{
            Name = 'UpdateDepartmentAttributes'
            Type = 'IdLE.Step.EnsureAttributes'
            With = @{
                AuthSessionName    = 'MicrosoftGraph'
                AuthSessionOptions = @{ Role = 'Admin' }
                IdentityKey        = '{{Request.Input.UserObjectId}}'
                Attributes         = @{
                    Department = '{{Request.Input.NewDepartment}}'
                }
            }
        }
        @{
            Name = 'UpdateJobTitle'
            Type = 'IdLE.Step.EnsureAttributes'
            Condition = @{
                All = @(
                    @{
                        Exists = 'Request.Input.NewJobTitle'
                    }
                )
            }
            With = @{
                AuthSessionName    = 'MicrosoftGraph'
                AuthSessionOptions = @{ Role = 'Admin' }
                IdentityKey        = '{{Request.Input.UserObjectId}}'
                Attributes         = @{
                    JobTitle = '{{Request.Input.NewJobTitle}}'
                }
            }
        }
        @{
            Name = 'UpdateOfficeLocation'
            Type = 'IdLE.Step.EnsureAttributes'
            Condition = @{
                All = @(
                    @{
                        Exists = 'Request.Input.NewOfficeLocation'
                    }
                )
            }
            With = @{
                AuthSessionName    = 'MicrosoftGraph'
                AuthSessionOptions = @{ Role = 'Admin' }
                IdentityKey        = '{{Request.Input.UserObjectId}}'
                Attributes         = @{
                    OfficeLocation = '{{Request.Input.NewOfficeLocation}}'
                }
            }
        }
        @{
            Name = 'UpdateGroupMemberships'
            Type = 'IdLE.Step.EnsureEntitlement'
            With = @{
                AuthSessionName    = 'MicrosoftGraph'
                AuthSessionOptions = @{ Role = 'Admin' }
                IdentityKey        = '{{Request.Input.UserObjectId}}'
                Desired            = @(
                    @{
                        Kind        = 'Group'
                        Id          = '{{Request.Input.NewDepartmentGroupId}}'
                        DisplayName = '{{Request.Input.NewDepartment}}'
                    }
                )
                Remove             = @(
                    @{
                        Kind        = 'Group'
                        Id          = '{{Request.Input.OldDepartmentGroupId}}'
                        DisplayName = '{{Request.Input.OldDepartment}}'
                    }
                )
            }
        }
        @{
            Name = 'UpdateManager'
            Type = 'IdLE.Step.EnsureAttributes'
            Condition = @{
                All = @(
                    @{
                        Exists = 'Request.Input.NewManagerId'
                    }
                )
            }
            With = @{
                AuthSessionName    = 'MicrosoftGraph'
                AuthSessionOptions = @{ Role = 'Admin' }
                IdentityKey        = '{{Request.Input.UserObjectId}}'
                Attributes         = @{
                    Manager = '{{Request.Input.NewManagerId}}'
                }
            }
        }
        @{
            Name = 'EmitCompletionEvent'
            Type = 'IdLE.Step.EmitEvent'
            With = @{
                Message = 'EntraID user {{Request.Input.UserObjectId}} moved to new department successfully.'
            }
        }
    )
}

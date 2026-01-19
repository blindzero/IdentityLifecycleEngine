@{
    Name           = 'EntraID Mover - Department Change'
    LifecycleEvent = 'Mover'
    Description    = 'Updates user attributes and group memberships when user moves to new department.'
    Steps          = @(
        @{
            Name = 'UpdateDepartmentAttributes'
            Type = 'IdLE.Step.EnsureAttribute'
            With = @{
                AuthSessionName    = 'MicrosoftGraph'
                AuthSessionOptions = @{ Role = 'Admin' }
                IdentityKey        = '{{Request.Input.UserObjectId}}'
                Name               = 'Department'
                Value              = '{{Request.Input.NewDepartment}}'
            }
        }
        @{
            Name = 'UpdateJobTitle'
            Type = 'IdLE.Step.EnsureAttribute'
            Condition = @{
                Type  = 'Expression'
                Value = '{{Request.Input.NewJobTitle}} -ne $null'
            }
            With = @{
                AuthSessionName    = 'MicrosoftGraph'
                AuthSessionOptions = @{ Role = 'Admin' }
                IdentityKey        = '{{Request.Input.UserObjectId}}'
                Name               = 'JobTitle'
                Value              = '{{Request.Input.NewJobTitle}}'
            }
        }
        @{
            Name = 'UpdateOfficeLocation'
            Type = 'IdLE.Step.EnsureAttribute'
            Condition = @{
                Type  = 'Expression'
                Value = '{{Request.Input.NewOfficeLocation}} -ne $null'
            }
            With = @{
                AuthSessionName    = 'MicrosoftGraph'
                AuthSessionOptions = @{ Role = 'Admin' }
                IdentityKey        = '{{Request.Input.UserObjectId}}'
                Name               = 'OfficeLocation'
                Value              = '{{Request.Input.NewOfficeLocation}}'
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
            Type = 'IdLE.Step.EnsureAttribute'
            Condition = @{
                Type  = 'Expression'
                Value = '{{Request.Input.NewManagerId}} -ne $null'
            }
            With = @{
                AuthSessionName    = 'MicrosoftGraph'
                AuthSessionOptions = @{ Role = 'Admin' }
                IdentityKey        = '{{Request.Input.UserObjectId}}'
                Name               = 'Manager'
                Value              = '{{Request.Input.NewManagerId}}'
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

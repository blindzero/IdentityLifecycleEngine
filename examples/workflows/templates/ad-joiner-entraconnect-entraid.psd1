@{
    Name           = 'Scenario - Joiner with Entra Connect Sync (AD + Entra ID)'
    LifecycleEvent = 'Joiner'
    Description    = 'Creates an AD account, triggers Entra Connect delta sync, then assigns an Entra ID group. Demonstrates multi-provider orchestration.'

    Steps          = @(
        @{
            Name = 'Create AD account'
            Type = 'IdLE.Step.CreateIdentity'
            With = @{
                Provider         = 'Directory'
                AuthSessionName  = '{{Request.Input.Auth.Directory}}'

                IdentityKey      = '{{Request.Input.SamAccountName}}'

                Attributes       = @{
                    GivenName   = '{{Request.Input.GivenName}}'
                    Surname     = '{{Request.Input.Surname}}'
                    Department  = '{{Request.Input.Department}}'
                }
            }
        }

        @{
            Name = 'Trigger Entra Connect Delta Sync'
            Type = 'IdLE.Step.TriggerDirectorySync'
            With = @{
                Provider            = 'DirectorySync'
                AuthSessionName     = 'EntraConnect'
                AuthSessionOptions  = @{
                    Role = 'EntraConnectAdmin'
                }

                PolicyType          = 'Delta'
                Wait                = $true
                TimeoutSeconds      = 300
                PollIntervalSeconds = 10
            }
        }

        @{
            Name = 'Assign Entra ID group membership'
            Type = 'IdLE.Step.EnsureEntitlement'
            With = @{
                Provider            = 'Identity'
                AuthSessionName     = 'MicrosoftGraph'
                AuthSessionOptions  = @{
                    Role = 'Admin'
                }

                IdentityKey         = '{{Request.Input.UserPrincipalName}}'

                Desired             = @(
                    @{
                        Kind        = 'Group'
                        Id          = '{{Request.Input.AllEmployeesGroupId}}'
                        DisplayName = '{{Request.Input.AllEmployeesGroupName}}'
                    }
                )
            }
        }
    )
}

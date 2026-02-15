@{
    Name           = 'Complete Joiner - EntraID + ExchangeOnline Offboarding'
    LifecycleEvent = 'Joiner'
    Description = 'AD joiner workflow template (safe defaults).'

    Steps = @(
        # --- Identity creation / baseline ---
        @{
            Type = 'IdLE.Step.CreateIdentity'
            Name     = 'Create identity (if missing)'
            With     = @{
                # Required by the provider: which auth session to use
                AuthSessionName = '{{Request.Auth.Directory}}'

                # Provider-specific: identify the target identity
                # The exact key names depend on provider contracts; keep it consistent with your provider docs.
                IdentityKey  = '{{Request.Input.SamAccountName}}'

                # Optional: initial attributes that are commonly required
                Attributes = @{
                    GivenName   = '{{Request.Input.GivenName}}'
                    Surname     = '{{Request.Input.Surname}}'
                    DisplayName = '{{Request.Input.DisplayName}}'
                }
            }
        }

        @{
            Type = 'IdLE.Step.EnsureAttributes'
            Name     = 'Ensure core attributes'
            With     = @{
                AuthSessionName = '{{Request.Auth.Directory}}'
                IdentityKey         = '{{Request.Input.SamAccountName}}'

                Attributes = @{
                    Mail            = '{{Request.Input.Mail}}'
                    Department      = '{{Request.Input.Department}}'
                    Title           = '{{Request.Input.Title}}'
                    Company         = '{{Request.Input.Company}}'
                    Office          = '{{Request.Input.Office}}'
                    Manager         = '{{Request.Input.ManagerSamAccountName}}'
                    TelephoneNumber = '{{Request.Input.Phone}}'
                }
            }
        }

        @{
            Type = 'IdLE.Step.EnsureEntitlement'
            Name = 'Ensure baseline group membership (1)'
            With = @{
                AuthSessionName = '{{Request.Auth.Directory}}'
                IdentityKey     = '{{Request.Input.SamAccountName}}'
                Entitlement     = @{
                    Kind = 'Group';
                    Id = '{{Request.Input.BaselineGroups.0}}';
                    DisplayName = '{{Request.Input.BaselineGroups.0}}'
                }
                State           = 'Present'
            }
        },
        @{
            Type = 'IdLE.Step.EnsureEntitlement'
            Name = 'Ensure baseline group membership (2)'
            With = @{
                AuthSessionName = '{{Request.Auth.Directory}}'
                IdentityKey     = '{{Request.Input.SamAccountName}}'
                Entitlement     = @{
                    Kind = 'Group';
                    Id = '{{Request.Input.BaselineGroups.1}}';
                    DisplayName = '{{Request.Input.BaselineGroups.1}}'
                }
                State           = 'Present'
            }
        }

        # --- Optional: Mover patterns (disabled by default) ---
        # Use one of these approaches:
        # A) Guard execution via a flag (preferred)
        # B) Keep steps commented out and enable when needed

        @{
            Type = 'IdLE.Step.EnsureAttributes'
            Name     = 'Mover: update org attributes (optional)'
            With     = @{
                # Guard by convention: only run when request indicates mover
                Condition       = '{{Request.Input.IsMover}}'
                AuthSessionName = '{{Request.Auth.Directory}}'
                IdentityKey         = '{{Request.Input.SamAccountName}}'
                Attributes      = @{
                    Department  = '{{Request.Input.NewDepartment}}'
                    Title       = '{{Request.Input.NewTitle}}'
                    Office      = '{{Request.Input.NewOffice}}'
                    Manager     = '{{Request.Input.NewManagerSamAccountName}}'
                    Description = 'Moved on {{Request.Execution.Timestamp}}'
                }
            }
        }

        @{
            Type = 'IdLE.Step.EnsureEntitlement'
            Name     = 'Mover: adjust group memberships (optional, baseline 1)'
            With     = @{
                Condition       = '{{Request.Input.IsMover}}'
                AuthSessionName = '{{Request.Auth.Directory}}'
                IdentityKey         = '{{Request.Input.SamAccountName}}'

                # Optional: baseline + department-specific groups.
                Entitlement = @{ Kind = 'Group'; Id = '{{Request.Input.BaselineGroups.0}}' }
                State = 'Present'
            }
        }
        @{
            Type = 'IdLE.Step.EnsureEntitlement'
            Name     = 'Mover: adjust group memberships (optional, baseline 2)'
            With     = @{
                Condition       = '{{Request.Input.IsMover}}'
                AuthSessionName = '{{Request.Auth.Directory}}'
                IdentityKey         = '{{Request.Input.SamAccountName}}'

                # Optional: baseline + department-specific groups.
                Entitlement = @{ Kind = 'Group'; Id = '{{Request.Input.BaselineGroups.1}}' }
                State = 'Present'
            }
        }
        @{
            Type = 'IdLE.Step.EnsureEntitlement'
            Name     = 'Mover: adjust group memberships (optional, department 1)'
            With     = @{
                Condition       = '{{Request.Input.IsMover}}'
                AuthSessionName = '{{Request.Auth.Directory}}'
                IdentityKey         = '{{Request.Input.SamAccountName}}'

                # Optional: baseline + department-specific groups.
                Entitlement = @{ Kind = 'Group'; Id = '{{Request.Input.DepartmentGroups.0}}' }
                State = 'Present'
            }
        }
        @{
            Type = 'IdLE.Step.EnsureEntitlement'
            Name     = 'Mover: adjust group memberships (optional, department 2)'
            With     = @{
                Condition       = '{{Request.Input.IsMover}}'
                AuthSessionName = '{{Request.Auth.Directory}}'
                IdentityKey         = '{{Request.Input.SamAccountName}}'

                # Optional: baseline + department-specific groups.
                Entitlement = @{ Kind = 'Group'; Id = '{{Request.Input.DepartmentGroups.1}}' }
                State = 'Present'
            }
        }
    )
}
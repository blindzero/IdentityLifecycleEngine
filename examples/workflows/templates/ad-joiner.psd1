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
                IdentityKey  = '{{Request.Intent.SamAccountName}}'

                # Optional: initial attributes that are commonly required
                Attributes = @{
                    GivenName   = '{{Request.Intent.GivenName}}'
                    Surname     = '{{Request.Intent.Surname}}'
                    DisplayName = '{{Request.Intent.DisplayName}}'
                }
            }
        }

        @{
            Type = 'IdLE.Step.EnsureAttributes'
            Name     = 'Ensure core attributes'
            With     = @{
                AuthSessionName = '{{Request.Auth.Directory}}'
                IdentityKey         = '{{Request.Intent.SamAccountName}}'

                Attributes = @{
                    Mail            = '{{Request.Intent.Mail}}'
                    Department      = '{{Request.Intent.Department}}'
                    Title           = '{{Request.Intent.Title}}'
                    Company         = '{{Request.Intent.Company}}'
                    Office          = '{{Request.Intent.Office}}'
                    Manager         = '{{Request.Intent.ManagerSamAccountName}}'
                    TelephoneNumber = '{{Request.Intent.Phone}}'
                }
            }
        }

        @{
            Type = 'IdLE.Step.EnsureEntitlement'
            Name = 'Ensure baseline group membership (1)'
            With = @{
                AuthSessionName = '{{Request.Auth.Directory}}'
                IdentityKey     = '{{Request.Intent.SamAccountName}}'
                Entitlement     = @{
                    Kind = 'Group';
                    Id = '{{Request.Intent.BaselineGroups.0}}';
                    DisplayName = '{{Request.Intent.BaselineGroups.0}}'
                }
                State           = 'Present'
            }
        },
        @{
            Type = 'IdLE.Step.EnsureEntitlement'
            Name = 'Ensure baseline group membership (2)'
            With = @{
                AuthSessionName = '{{Request.Auth.Directory}}'
                IdentityKey     = '{{Request.Intent.SamAccountName}}'
                Entitlement     = @{
                    Kind = 'Group';
                    Id = '{{Request.Intent.BaselineGroups.1}}';
                    DisplayName = '{{Request.Intent.BaselineGroups.1}}'
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
                Condition       = '{{Request.Intent.IsMover}}'
                AuthSessionName = '{{Request.Auth.Directory}}'
                IdentityKey         = '{{Request.Intent.SamAccountName}}'
                Attributes      = @{
                    Department  = '{{Request.Intent.NewDepartment}}'
                    Title       = '{{Request.Intent.NewTitle}}'
                    Office      = '{{Request.Intent.NewOffice}}'
                    Manager     = '{{Request.Intent.NewManagerSamAccountName}}'
                    Description = 'Moved on {{Request.Execution.Timestamp}}'
                }
            }
        }

        @{
            Type = 'IdLE.Step.EnsureEntitlement'
            Name     = 'Mover: adjust group memberships (optional, baseline 1)'
            With     = @{
                Condition       = '{{Request.Intent.IsMover}}'
                AuthSessionName = '{{Request.Auth.Directory}}'
                IdentityKey         = '{{Request.Intent.SamAccountName}}'

                # Optional: baseline + department-specific groups.
                Entitlement = @{ Kind = 'Group'; Id = '{{Request.Intent.BaselineGroups.0}}' }
                State = 'Present'
            }
        }
        @{
            Type = 'IdLE.Step.EnsureEntitlement'
            Name     = 'Mover: adjust group memberships (optional, baseline 2)'
            With     = @{
                Condition       = '{{Request.Intent.IsMover}}'
                AuthSessionName = '{{Request.Auth.Directory}}'
                IdentityKey         = '{{Request.Intent.SamAccountName}}'

                # Optional: baseline + department-specific groups.
                Entitlement = @{ Kind = 'Group'; Id = '{{Request.Intent.BaselineGroups.1}}' }
                State = 'Present'
            }
        }
        @{
            Type = 'IdLE.Step.EnsureEntitlement'
            Name     = 'Mover: adjust group memberships (optional, department 1)'
            With     = @{
                Condition       = '{{Request.Intent.IsMover}}'
                AuthSessionName = '{{Request.Auth.Directory}}'
                IdentityKey         = '{{Request.Intent.SamAccountName}}'

                # Optional: baseline + department-specific groups.
                Entitlement = @{ Kind = 'Group'; Id = '{{Request.Intent.DepartmentGroups.0}}' }
                State = 'Present'
            }
        }
        @{
            Type = 'IdLE.Step.EnsureEntitlement'
            Name     = 'Mover: adjust group memberships (optional, department 2)'
            With     = @{
                Condition       = '{{Request.Intent.IsMover}}'
                AuthSessionName = '{{Request.Auth.Directory}}'
                IdentityKey         = '{{Request.Intent.SamAccountName}}'

                # Optional: baseline + department-specific groups.
                Entitlement = @{ Kind = 'Group'; Id = '{{Request.Intent.DepartmentGroups.1}}' }
                State = 'Present'
            }
        }
    )
}
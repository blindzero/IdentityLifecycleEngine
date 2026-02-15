@{
    Name           = 'Complete Joiner - EntraID + ExchangeOnline Offboarding'
    LifecycleEvent = 'Joiner'
    Description = 'AD joiner workflow template (safe defaults).'

    Steps = @(
        # --- Identity creation / baseline ---
        @{
            StepType = 'IdLE.Step.CreateIdentity'
            Name     = 'Create identity (if missing)'
            With     = @{
                # Required by the provider: which auth session to use
                AuthSessionName = '{{Request.Auth.Directory}}'

                # Provider-specific: identify the target identity
                # The exact key names depend on provider contracts; keep it consistent with your provider docs.
                Identity = @{
                    SamAccountName   = '{{Request.Input.SamAccountName}}'
                    UserPrincipalName = '{{Request.Input.UserPrincipalName}}'
                }

                # Optional: initial attributes that are commonly required
                Attributes = @{
                    GivenName   = '{{Request.Input.GivenName}}'
                    Surname     = '{{Request.Input.Surname}}'
                    DisplayName = '{{Request.Input.DisplayName}}'
                }
            }
        }

        @{
            StepType = 'IdLE.Step.EnsureAttributes'
            Name     = 'Ensure core attributes'
            With     = @{
                AuthSessionName = '{{Request.Auth.Directory}}'
                Identity        = @{
                    SamAccountName = '{{Request.Input.SamAccountName}}'
                }
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
            StepType = 'IdLE.Step.EnsureEntitlements'
            Name     = 'Ensure baseline group memberships'
            With     = @{
                AuthSessionName = '{{Request.Auth.Directory}}'
                Identity        = @{
                    SamAccountName = '{{Request.Input.SamAccountName}}'
                }

                # Use explicit, predictable lists. Prefer allow-lists for baseline access.
                Entitlements = @(
                    '{{Request.Input.BaselineGroups.0}}'
                    '{{Request.Input.BaselineGroups.1}}'
                )
            }
        }

        # --- Optional: Mover patterns (disabled by default) ---
        # Use one of these approaches:
        # A) Guard execution via a flag (preferred)
        # B) Keep steps commented out and enable when needed

        @{
            StepType = 'IdLE.Step.EnsureAttributes'
            Name     = 'Mover: update org attributes (optional)'
            With     = @{
                # Guard by convention: only run when request indicates mover
                Condition       = '{{Request.Input.IsMover}}'
                AuthSessionName = '{{Request.Auth.Directory}}'
                Identity        = @{ SamAccountName = '{{Request.Input.SamAccountName}}' }
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
            StepType = 'IdLE.Step.EnsureEntitlement'
            Name     = 'Mover: adjust group memberships (optional)'
            With     = @{
                Condition       = '{{Request.Input.IsMover}}'
                AuthSessionName = '{{Request.Auth.Directory}}'
                Identity        = @{ SamAccountName = '{{Request.Input.SamAccountName}}' }

                # Optional: baseline + department-specific groups.
                Entitlements = @(
                    '{{Request.Input.BaselineGroups.0}}'
                    '{{Request.Input.BaselineGroups.1}}'
                    '{{Request.Input.DepartmentGroups.0}}'
                    '{{Request.Input.DepartmentGroups.1}}'
                )
            }
        }
    )
}
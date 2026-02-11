@{
    Name           = 'Joiner - AD Complete Workflow'
    LifecycleEvent = 'Joiner'
    Steps          = @(
        @{
            Name = 'Create AD user account'
            Type = 'IdLE.Step.CreateIdentity'
            With = @{
                IdentityKey = 'newuser'
                Attributes  = @{
                    SamAccountName    = 'newuser'
                    UserPrincipalName = 'newuser@contoso.local'
                    GivenName         = 'New'
                    Surname           = 'User'
                    DisplayName       = 'New User'
                    Description       = 'New employee account'
                    Path              = 'OU=Joiners,OU=Users,DC=contoso,DC=local'
                    
                    # Enable account to trigger automatic password generation
                    # When Enabled = $true and no password is provided, the provider automatically:
                    # - Reads domain password policy via Get-ADDefaultDomainPasswordPolicy
                    # - Falls back to configurable rules if policy cannot be read
                    # - Generates a compliant password (min length 24, complexity enabled)
                    # - Returns GeneratedAccountPasswordProtected (DPAPI-scoped) by default
                    Enabled           = $true
                    
                    # Optional: Request plaintext password in result (for displaying to onboarding staff)
                    # WARNING: Results containing plaintext must not be persisted to disk/logs
                    # AllowPlainTextPasswordOutput = $true
                    
                    # Optional: Disable password reset on first login (default: $true)
                    # Useful for hybrid scenarios where remote login may require stable password
                    # ResetOnFirstLogin = $false
                    
                    OtherAttributes   = @{
                        # Custom LDAP attributes for organization-specific needs
                        employeeType        = 'Employee'
                        extensionAttribute1 = 'EMPL-2024-001'
                        company             = 'Contoso Ltd'
                    }
                }
                # Provider alias - references the key in the provider hashtable.
                # The host chooses this name when creating the provider hashtable.
                # If omitted, defaults to 'Identity'.
                Provider    = 'Identity'
            }
            # After execution, when password was generated, the result will contain:
            # - PasswordGenerated: $true
            # - PasswordGenerationPolicyUsed: 'DomainPolicy' or 'Fallback'
            # - GeneratedAccountPasswordProtected: DPAPI-scoped ProtectedString (safe for reveal)
            # - GeneratedAccountPasswordPlainText: (only if AllowPlainTextPasswordOutput = $true)
            #
            # To reveal the password from ProtectedString:
            # $secure = ConvertTo-SecureString -String $result.GeneratedAccountPasswordProtected
            # $plain = [pscredential]::new('x', $secure).GetNetworkCredential().Password
        },
        @{
            Name = 'Set Department and Title'
            Type = 'IdLE.Step.EnsureAttributes'
            With = @{
                IdentityKey = 'newuser@contoso.local'
                Attributes  = @{
                    Department = 'IT'
                    Title      = 'Software Engineer'
                }
                Provider    = 'Identity'
            }
        },
        @{
            Name = 'Grant base access group'
            Type = 'IdLE.Step.EnsureEntitlement'
            With = @{
                IdentityKey = 'newuser@contoso.local'
                Entitlement = @{
                    Kind        = 'Group'
                    Id          = 'CN=All-Employees,OU=Groups,DC=contoso,DC=local'
                    DisplayName = 'All Employees'
                }
                State       = 'Present'
                Provider    = 'Identity'
            }
        },
        @{
            Name = 'Grant IT department group'
            Type = 'IdLE.Step.EnsureEntitlement'
            With = @{
                IdentityKey = 'newuser@contoso.local'
                Entitlement = @{
                    Kind        = 'Group'
                    Id          = 'CN=IT-Department,OU=Groups,DC=contoso,DC=local'
                    DisplayName = 'IT Department'
                }
                State       = 'Present'
                Provider    = 'Identity'
            }
        },
        @{
            Name = 'Move to active users OU'
            Type = 'IdLE.Step.MoveIdentity'
            With = @{
                IdentityKey     = 'newuser@contoso.local'
                TargetContainer = 'OU=Active,OU=Users,DC=contoso,DC=local'
                Provider        = 'Identity'
            }
        }
    )
}

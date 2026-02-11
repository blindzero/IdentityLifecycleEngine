@{
    Name           = 'Joiner - AD Account with Password Generation'
    LifecycleEvent = 'Joiner'
    Description    = 'Example demonstrating automatic password generation for AD accounts'
    Steps          = @(
        @{
            Name = 'Create enabled AD account with automatic password generation'
            Type = 'IdLE.Step.CreateIdentity'
            With = @{
                IdentityKey = 'jdoe'
                Attributes  = @{
                    SamAccountName    = 'jdoe'
                    UserPrincipalName = 'jdoe@contoso.local'
                    GivenName         = 'John'
                    Surname           = 'Doe'
                    DisplayName       = 'John Doe'
                    Department        = 'Engineering'
                    Title             = 'Software Engineer'
                    Path              = 'OU=Joiners,OU=Users,DC=contoso,DC=local'
                    
                    # Enable the account to trigger password generation
                    Enabled           = $true
                    
                    # Optional: Allow plaintext password in result (for displaying to onboarding staff)
                    # Default behavior: returns only ProtectedString (DPAPI-scoped)
                    # AllowPlainTextPasswordOutput = $true
                    
                    # Optional: Control reset on first login (default: $true when password is set/generated)
                    # ResetOnFirstLogin = $false
                }
                Provider    = 'Identity'
            }
            # After execution, the result will contain:
            # - PasswordGenerated: $true
            # - PasswordGenerationPolicyUsed: 'DomainPolicy' or 'Fallback'
            # - GeneratedAccountPasswordProtected: DPAPI-scoped ProtectedString
            # - GeneratedAccountPasswordPlainText: (only if AllowPlainTextPasswordOutput = $true)
        },
        @{
            Name = 'Example: Create account with plaintext password output'
            Type = 'IdLE.Step.CreateIdentity'
            With = @{
                IdentityKey = 'jsmith'
                Attributes  = @{
                    SamAccountName               = 'jsmith'
                    UserPrincipalName            = 'jsmith@contoso.local'
                    GivenName                    = 'Jane'
                    Surname                      = 'Smith'
                    DisplayName                  = 'Jane Smith'
                    Path                         = 'OU=Joiners,OU=Users,DC=contoso,DC=local'
                    Enabled                      = $true
                    
                    # Opt-in to plaintext password in result
                    AllowPlainTextPasswordOutput = $true
                }
                Provider    = 'Identity'
            }
            # Result will include GeneratedAccountPasswordPlainText for immediate access
            # WARNING: Results containing plaintext must not be persisted to disk/logs
        },
        @{
            Name = 'Example: Create account without password reset requirement'
            Type = 'IdLE.Step.CreateIdentity'
            With = @{
                IdentityKey = 'remote-admin'
                Attributes  = @{
                    SamAccountName    = 'remote-admin'
                    UserPrincipalName = 'remote-admin@contoso.local'
                    GivenName         = 'Remote'
                    Surname           = 'Admin'
                    DisplayName       = 'Remote Admin Account'
                    Path              = 'OU=Admins,DC=contoso,DC=local'
                    Enabled           = $true
                    
                    # Disable "must change password at next logon" for hybrid scenarios
                    ResetOnFirstLogin = $false
                }
                Provider    = 'Identity'
            }
        },
        @{
            Name = 'Example: Create disabled account (no password generation)'
            Type = 'IdLE.Step.CreateIdentity'
            With = @{
                IdentityKey = 'staging-user'
                Attributes  = @{
                    SamAccountName    = 'staging-user'
                    UserPrincipalName = 'staging-user@contoso.local'
                    GivenName         = 'Staging'
                    Surname           = 'User'
                    DisplayName       = 'Staging User'
                    Path              = 'OU=Staging,DC=contoso,DC=local'
                    
                    # Disabled accounts do not trigger password generation
                    Enabled           = $false
                }
                Provider    = 'Identity'
            }
            # No password will be generated for disabled accounts
        }
    )
}

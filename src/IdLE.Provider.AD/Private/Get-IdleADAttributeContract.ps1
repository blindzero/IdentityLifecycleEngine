function Get-IdleADAttributeContract {
    <#
    .SYNOPSIS
    Returns the supported attribute contract for AD Provider operations.

    .DESCRIPTION
    Defines which attributes are supported for CreateIdentity and EnsureAttributes operations.
    This contract serves as the single source of truth for attribute validation.

    Each entry includes:
    - Target: 'Parameter' (Set-ADUser/New-ADUser named parameter) or 'Container' (special handling)
    - Type: expected value type
    - Required: whether the attribute is required
    - LdapField: the verified LDAP schema attribute name (used for -Clear/-Replace in Set-ADUser)

    For CreateIdentity, attributes map to New-ADUser named parameters.
    For EnsureAttributes, attributes map to Set-ADUser named parameters.
    Custom LDAP attributes not listed here can be set via the OtherAttributes container
    (keys must be valid LDAP attribute names, e.g. 'mobile', 'telephoneNumber').

    .PARAMETER Operation
    The operation to get the contract for: 'CreateIdentity' or 'EnsureAttributes'.

    .OUTPUTS
    System.Collections.Hashtable
    Returns a hashtable where keys are supported attribute names and values contain metadata.

    .EXAMPLE
    $contract = Get-IdleADAttributeContract -Operation 'CreateIdentity'
    $supportedKeys = $contract.Keys

    .EXAMPLE
    $contract = Get-IdleADAttributeContract -Operation 'EnsureAttributes'
    $contract['GivenName'].LdapField   # Returns 'givenName'
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('CreateIdentity', 'EnsureAttributes')]
        [string] $Operation
    )

    if ($Operation -eq 'CreateIdentity') {
        return @{
            # Identity Attributes
            SamAccountName           = @{ Target = 'Parameter'; Type = 'String';              Required = $false; LdapField = 'sAMAccountName' }
            UserPrincipalName        = @{ Target = 'Parameter'; Type = 'String';              Required = $false; LdapField = 'userPrincipalName' }
            Path                     = @{ Target = 'Parameter'; Type = 'String';              Required = $false; LdapField = $null }

            # Name Attributes
            Name                     = @{ Target = 'Parameter'; Type = 'String';              Required = $false; LdapField = 'cn' }
            GivenName                = @{ Target = 'Parameter'; Type = 'String';              Required = $false; LdapField = 'givenName' }
            Surname                  = @{ Target = 'Parameter'; Type = 'String';              Required = $false; LdapField = 'sn' }
            DisplayName              = @{ Target = 'Parameter'; Type = 'String';              Required = $false; LdapField = 'displayName' }

            # Organizational Attributes
            Description              = @{ Target = 'Parameter'; Type = 'String';              Required = $false; LdapField = 'description' }
            Department               = @{ Target = 'Parameter'; Type = 'String';              Required = $false; LdapField = 'department' }
            Title                    = @{ Target = 'Parameter'; Type = 'String';              Required = $false; LdapField = 'title' }

            # Contact Attributes
            EmailAddress             = @{ Target = 'Parameter'; Type = 'String';              Required = $false; LdapField = 'mail' }

            # Relationship Attributes
            Manager                  = @{ Target = 'Parameter'; Type = 'String';              Required = $false; LdapField = 'manager' }

            # Password Attributes
            AccountPassword          = @{ Target = 'Parameter'; Type = 'SecureString|String'; Required = $false; LdapField = $null }
            AccountPasswordAsPlainText = @{ Target = 'Parameter'; Type = 'String';            Required = $false; LdapField = $null }
            ResetOnFirstLogin        = @{ Target = 'Parameter'; Type = 'Boolean';             Required = $false; LdapField = $null }
            AllowPlainTextPasswordOutput = @{ Target = 'Parameter'; Type = 'Boolean';         Required = $false; LdapField = $null }

            # State Attributes
            Enabled                  = @{ Target = 'Parameter'; Type = 'Boolean';             Required = $false; LdapField = $null }

            # Extension Container (keys must be valid LDAP attribute names)
            OtherAttributes          = @{ Target = 'Container'; Type = 'Hashtable';           Required = $false; LdapField = $null }
        }
    }
    elseif ($Operation -eq 'EnsureAttributes') {
        return @{
            # Name Attributes
            GivenName                = @{ Target = 'Parameter'; Type = 'String';  Required = $false; LdapField = 'givenName' }
            Surname                  = @{ Target = 'Parameter'; Type = 'String';  Required = $false; LdapField = 'sn' }
            DisplayName              = @{ Target = 'Parameter'; Type = 'String';  Required = $false; LdapField = 'displayName' }
            Initials                 = @{ Target = 'Parameter'; Type = 'String';  Required = $false; LdapField = 'initials' }

            # Identity Attributes
            SamAccountName           = @{ Target = 'Parameter'; Type = 'String';  Required = $false; LdapField = 'sAMAccountName' }
            UserPrincipalName        = @{ Target = 'Parameter'; Type = 'String';  Required = $false; LdapField = 'userPrincipalName' }

            # Organizational Attributes
            Description              = @{ Target = 'Parameter'; Type = 'String';  Required = $false; LdapField = 'description' }
            Department               = @{ Target = 'Parameter'; Type = 'String';  Required = $false; LdapField = 'department' }
            Title                    = @{ Target = 'Parameter'; Type = 'String';  Required = $false; LdapField = 'title' }
            Company                  = @{ Target = 'Parameter'; Type = 'String';  Required = $false; LdapField = 'company' }
            Division                 = @{ Target = 'Parameter'; Type = 'String';  Required = $false; LdapField = 'division' }
            Office                   = @{ Target = 'Parameter'; Type = 'String';  Required = $false; LdapField = 'physicalDeliveryOfficeName' }
            EmployeeID               = @{ Target = 'Parameter'; Type = 'String';  Required = $false; LdapField = 'employeeID' }
            EmployeeNumber           = @{ Target = 'Parameter'; Type = 'String';  Required = $false; LdapField = 'employeeNumber' }

            # Contact Attributes
            EmailAddress             = @{ Target = 'Parameter'; Type = 'String';  Required = $false; LdapField = 'mail' }
            OfficePhone              = @{ Target = 'Parameter'; Type = 'String';  Required = $false; LdapField = 'telephoneNumber' }
            MobilePhone              = @{ Target = 'Parameter'; Type = 'String';  Required = $false; LdapField = 'mobile' }
            HomePhone                = @{ Target = 'Parameter'; Type = 'String';  Required = $false; LdapField = 'homePhone' }
            Fax                      = @{ Target = 'Parameter'; Type = 'String';  Required = $false; LdapField = 'facsimileTelephoneNumber' }

            # Address Attributes
            StreetAddress            = @{ Target = 'Parameter'; Type = 'String';  Required = $false; LdapField = 'streetAddress' }
            City                     = @{ Target = 'Parameter'; Type = 'String';  Required = $false; LdapField = 'l' }
            State                    = @{ Target = 'Parameter'; Type = 'String';  Required = $false; LdapField = 'st' }
            PostalCode               = @{ Target = 'Parameter'; Type = 'String';  Required = $false; LdapField = 'postalCode' }
            Country                  = @{ Target = 'Parameter'; Type = 'String';  Required = $false; LdapField = 'co' }
            POBox                    = @{ Target = 'Parameter'; Type = 'String';  Required = $false; LdapField = 'postOfficeBox' }

            # Web / Profile Attributes
            HomePage                 = @{ Target = 'Parameter'; Type = 'String';  Required = $false; LdapField = 'wWWHomePage' }

            # Relationship Attributes
            Manager                  = @{ Target = 'Parameter'; Type = 'String';  Required = $false; LdapField = 'manager' }

            # Account / Profile Path Attributes
            HomeDirectory            = @{ Target = 'Parameter'; Type = 'String';  Required = $false; LdapField = 'homeDirectory' }
            HomeDrive                = @{ Target = 'Parameter'; Type = 'String';  Required = $false; LdapField = 'homeDrive' }
            ProfilePath              = @{ Target = 'Parameter'; Type = 'String';  Required = $false; LdapField = 'profilePath' }
            ScriptPath               = @{ Target = 'Parameter'; Type = 'String';  Required = $false; LdapField = 'scriptPath' }

            # Extension Container (keys must be valid LDAP attribute names, e.g. 'mobile', 'telephoneNumber')
            OtherAttributes          = @{ Target = 'Container'; Type = 'Hashtable'; Required = $false; LdapField = $null }
        }
    }
}

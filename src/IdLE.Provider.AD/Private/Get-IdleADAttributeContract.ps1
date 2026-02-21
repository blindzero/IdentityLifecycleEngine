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
    - LdapField: the verified LDAP schema attribute name, resolved via Get-IdleADAttributeLDAPField

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
    $contract['GivenName'].LdapField   # Returns 'givenName' via Get-IdleADAttributeLDAPField
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('CreateIdentity', 'EnsureAttributes')]
        [string] $Operation
    )

    if ($Operation -eq 'CreateIdentity') {
        $contract = @{
            # Identity Attributes
            SamAccountName           = @{ Target = 'Parameter'; Type = 'String';              Required = $false }
            UserPrincipalName        = @{ Target = 'Parameter'; Type = 'String';              Required = $false }
            Path                     = @{ Target = 'Parameter'; Type = 'String';              Required = $false }

            # Name Attributes
            Name                     = @{ Target = 'Parameter'; Type = 'String';              Required = $false }
            GivenName                = @{ Target = 'Parameter'; Type = 'String';              Required = $false }
            Surname                  = @{ Target = 'Parameter'; Type = 'String';              Required = $false }
            DisplayName              = @{ Target = 'Parameter'; Type = 'String';              Required = $false }

            # Organizational Attributes
            Description              = @{ Target = 'Parameter'; Type = 'String';              Required = $false }
            Department               = @{ Target = 'Parameter'; Type = 'String';              Required = $false }
            Title                    = @{ Target = 'Parameter'; Type = 'String';              Required = $false }

            # Contact Attributes
            EmailAddress             = @{ Target = 'Parameter'; Type = 'String';              Required = $false }

            # Relationship Attributes
            Manager                  = @{ Target = 'Parameter'; Type = 'String';              Required = $false }

            # Password Attributes
            AccountPassword          = @{ Target = 'Parameter'; Type = 'SecureString|String'; Required = $false }
            AccountPasswordAsPlainText = @{ Target = 'Parameter'; Type = 'String';            Required = $false }
            ResetOnFirstLogin        = @{ Target = 'Parameter'; Type = 'Boolean';             Required = $false }
            AllowPlainTextPasswordOutput = @{ Target = 'Parameter'; Type = 'Boolean';         Required = $false }

            # State Attributes
            Enabled                  = @{ Target = 'Parameter'; Type = 'Boolean';             Required = $false }

            # Extension Container (keys must be valid LDAP attribute names)
            OtherAttributes          = @{ Target = 'Container'; Type = 'Hashtable';           Required = $false }
        }
    }
    elseif ($Operation -eq 'EnsureAttributes') {
        $contract = @{
            # Name Attributes
            GivenName                = @{ Target = 'Parameter'; Type = 'String';    Required = $false }
            Surname                  = @{ Target = 'Parameter'; Type = 'String';    Required = $false }
            DisplayName              = @{ Target = 'Parameter'; Type = 'String';    Required = $false }
            Initials                 = @{ Target = 'Parameter'; Type = 'String';    Required = $false }

            # Identity Attributes
            SamAccountName           = @{ Target = 'Parameter'; Type = 'String';    Required = $false }
            UserPrincipalName        = @{ Target = 'Parameter'; Type = 'String';    Required = $false }

            # Organizational Attributes
            Description              = @{ Target = 'Parameter'; Type = 'String';    Required = $false }
            Department               = @{ Target = 'Parameter'; Type = 'String';    Required = $false }
            Title                    = @{ Target = 'Parameter'; Type = 'String';    Required = $false }
            Company                  = @{ Target = 'Parameter'; Type = 'String';    Required = $false }
            Division                 = @{ Target = 'Parameter'; Type = 'String';    Required = $false }
            Office                   = @{ Target = 'Parameter'; Type = 'String';    Required = $false }
            EmployeeID               = @{ Target = 'Parameter'; Type = 'String';    Required = $false }
            EmployeeNumber           = @{ Target = 'Parameter'; Type = 'String';    Required = $false }

            # Contact Attributes
            EmailAddress             = @{ Target = 'Parameter'; Type = 'String';    Required = $false }
            OfficePhone              = @{ Target = 'Parameter'; Type = 'String';    Required = $false }
            MobilePhone              = @{ Target = 'Parameter'; Type = 'String';    Required = $false }
            HomePhone                = @{ Target = 'Parameter'; Type = 'String';    Required = $false }
            Fax                      = @{ Target = 'Parameter'; Type = 'String';    Required = $false }

            # Address Attributes
            StreetAddress            = @{ Target = 'Parameter'; Type = 'String';    Required = $false }
            City                     = @{ Target = 'Parameter'; Type = 'String';    Required = $false }
            State                    = @{ Target = 'Parameter'; Type = 'String';    Required = $false }
            PostalCode               = @{ Target = 'Parameter'; Type = 'String';    Required = $false }
            Country                  = @{ Target = 'Parameter'; Type = 'String';    Required = $false }
            POBox                    = @{ Target = 'Parameter'; Type = 'String';    Required = $false }

            # Web / Profile Attributes
            HomePage                 = @{ Target = 'Parameter'; Type = 'String';    Required = $false }

            # Relationship Attributes
            Manager                  = @{ Target = 'Parameter'; Type = 'String';    Required = $false }

            # Account / Profile Path Attributes
            HomeDirectory            = @{ Target = 'Parameter'; Type = 'String';    Required = $false }
            HomeDrive                = @{ Target = 'Parameter'; Type = 'String';    Required = $false }
            ProfilePath              = @{ Target = 'Parameter'; Type = 'String';    Required = $false }
            ScriptPath               = @{ Target = 'Parameter'; Type = 'String';    Required = $false }

            # Extension Container (keys must be valid LDAP attribute names, e.g. 'mobile', 'telephoneNumber')
            OtherAttributes          = @{ Target = 'Container'; Type = 'Hashtable'; Required = $false }
        }
    }

    # Enrich each Parameter entry with its LDAP field name from the dedicated mapping function
    foreach ($key in @($contract.Keys)) {
        if ($contract[$key].Target -eq 'Parameter') {
            $contract[$key]['LdapField'] = Get-IdleADAttributeLDAPField -AttributeName $key
        } else {
            $contract[$key]['LdapField'] = $null
        }
    }

    return $contract
}


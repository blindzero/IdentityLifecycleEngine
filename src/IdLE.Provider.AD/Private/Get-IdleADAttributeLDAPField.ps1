function Get-IdleADAttributeLDAPField {
    <#
    .SYNOPSIS
    Returns the verified LDAP attribute name for a given AD attribute key.

    .DESCRIPTION
    Provides the authoritative mapping from friendly AD attribute names (as used in the
    IdLE AD Provider contract) to their verified LDAP schema attribute names.

    LDAP names are verified against the Windows Server Active Directory LDAP schema.
    This mapping is used for -Clear, -Replace, and -Add operations in Set-ADUser to
    ensure correct attribute targeting in the directory.

    .PARAMETER AttributeName
    The friendly attribute name (PowerShell parameter name or contract key) to look up.

    .OUTPUTS
    System.String
    The LDAP attribute name, or $null if the attribute is not a named parameter mapping.

    .EXAMPLE
    Get-IdleADAttributeLDAPField -AttributeName 'GivenName'
    # Returns: 'givenName'

    .EXAMPLE
    Get-IdleADAttributeLDAPField -AttributeName 'EmailAddress'
    # Returns: 'mail'
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $AttributeName
    )

    # Verified against Windows Server Active Directory LDAP schema documentation.
    # Sources: RFC 4519, RFC 2798 (inetOrgPerson), MS-ADSC (Active Directory Schema Classes/Attributes).
    $ldapFields = @{
        # Name Attributes
        GivenName                = 'givenName'           # RFC 4519 section 2.12
        Surname                  = 'sn'                  # RFC 4519 section 2.32
        DisplayName              = 'displayName'         # MS-ADSC
        Initials                 = 'initials'            # RFC 2256

        # Identity Attributes
        SamAccountName           = 'sAMAccountName'      # MS-ADSC
        UserPrincipalName        = 'userPrincipalName'   # MS-ADSC

        # Organizational Attributes
        Description              = 'description'         # RFC 4519 section 2.5
        Department               = 'department'          # RFC 2798 section 2.2
        Title                    = 'title'               # RFC 4519 section 2.38
        Company                  = 'company'             # MS-ADSC
        Division                 = 'division'            # MS-ADSC
        Office                   = 'physicalDeliveryOfficeName' # RFC 4519 section 2.24
        Organization             = 'o'                   # RFC 4519 section 2.19
        EmployeeID               = 'employeeID'          # MS-ADSC
        EmployeeNumber           = 'employeeNumber'      # RFC 2798 section 2.5

        # Contact Attributes
        EmailAddress             = 'mail'                # RFC 2798 section 2.13
        OfficePhone              = 'telephoneNumber'     # RFC 4519 section 2.35
        MobilePhone              = 'mobile'              # RFC 2798 section 2.15
        HomePhone                = 'homePhone'           # RFC 2798 section 2.11
        Fax                      = 'facsimileTelephoneNumber' # RFC 4519 section 2.10

        # Address Attributes
        StreetAddress            = 'streetAddress'       # RFC 4519 section 2.34
        City                     = 'l'                   # RFC 4519 section 2.16 (localityName)
        State                    = 'st'                  # RFC 4519 section 2.33 (stateOrProvinceName)
        PostalCode               = 'postalCode'          # RFC 4519 section 2.23
        Country                  = 'co'                  # RFC 2256 section 5.4 (full country name)
        POBox                    = 'postOfficeBox'       # RFC 4519 section 2.25

        # Web / Profile Attributes
        HomePage                 = 'wWWHomePage'         # MS-ADSC

        # Relationship Attributes
        Manager                  = 'manager'             # RFC 4524 section 2.1

        # Account/Profile Path Attributes
        HomeDirectory            = 'homeDirectory'       # MS-ADSC
        HomeDrive                = 'homeDrive'           # MS-ADSC
        ProfilePath              = 'profilePath'         # MS-ADSC
        ScriptPath               = 'scriptPath'          # MS-ADSC
    }

    if ($ldapFields.ContainsKey($AttributeName)) {
        return $ldapFields[$AttributeName]
    }

    return $null
}

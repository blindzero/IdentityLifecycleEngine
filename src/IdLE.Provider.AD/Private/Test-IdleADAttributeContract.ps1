function Test-IdleADAttributeContract {
    <#
    .SYNOPSIS
    Validates attributes against the AD Provider attribute contract.

    .DESCRIPTION
    Performs strict validation of provided attributes against the supported attribute contract.
    Throws an exception if unsupported attributes are detected.

    .PARAMETER Attributes
    Hashtable of attributes to validate.

    .PARAMETER Operation
    The operation context: 'CreateIdentity' or 'EnsureAttribute'.

    .PARAMETER AttributeName
    For EnsureAttribute, the specific attribute name being set.

    .OUTPUTS
    System.Collections.Hashtable
    Returns a hashtable with validation results:
    - Requested: array of requested attribute keys
    - Supported: array of supported attribute keys
    - Unsupported: array of unsupported attribute keys

    .EXAMPLE
    $result = Test-IdleADAttributeContract -Attributes $attrs -Operation 'CreateIdentity'
    # Throws if unsupported attributes found

    .EXAMPLE
    $result = Test-IdleADAttributeContract -Operation 'EnsureAttribute' -AttributeName 'InvalidAttr'
    # Throws if attribute not supported for EnsureAttribute
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter()]
        [AllowNull()]
        [hashtable] $Attributes,

        [Parameter(Mandatory)]
        [ValidateSet('CreateIdentity', 'EnsureAttribute')]
        [string] $Operation,

        [Parameter()]
        [string] $AttributeName
    )

    $contract = Get-IdleADAttributeContract -Operation $Operation

    if ($Operation -eq 'CreateIdentity') {
        if ($null -eq $Attributes) {
            return @{
                Requested   = @()
                Supported   = @()
                Unsupported = @()
            }
        }

        $requestedKeys = @($Attributes.Keys)
        $supportedKeys = @($contract.Keys)
        $unsupportedKeys = @($requestedKeys | Where-Object { $_ -notin $supportedKeys })

        if ($unsupportedKeys.Count -gt 0) {
            $errorMessage = "AD Provider: Unsupported attributes in CreateIdentity operation.`n"
            $errorMessage += "Unsupported attributes: $($unsupportedKeys -join ', ')`n`n"
            $errorMessage += "Supported attributes for CreateIdentity:`n"
            $errorMessage += "  - Identity: SamAccountName, UserPrincipalName, Path`n"
            $errorMessage += "  - Name: Name, GivenName, Surname, DisplayName`n"
            $errorMessage += "  - Organization: Description, Department, Title`n"
            $errorMessage += "  - Contact: EmailAddress`n"
            $errorMessage += "  - Relationship: Manager`n"
            $errorMessage += "  - Password: AccountPassword, AccountPasswordAsPlainText`n"
            $errorMessage += "  - State: Enabled`n"
            $errorMessage += "  - Extension: OtherAttributes (hashtable of LDAP attributes)`n`n"
            $errorMessage += "To set custom LDAP attributes, use the 'OtherAttributes' container."

            throw $errorMessage
        }

        # Validate OtherAttributes if present
        if ($Attributes.ContainsKey('OtherAttributes')) {
            $otherAttrs = $Attributes['OtherAttributes']
            if ($null -ne $otherAttrs -and $otherAttrs -isnot [hashtable]) {
                throw "AD Provider: 'OtherAttributes' must be a hashtable. Received type: $($otherAttrs.GetType().FullName)"
            }
        }

        return @{
            Requested   = $requestedKeys
            Supported   = @($requestedKeys | Where-Object { $_ -in $supportedKeys })
            Unsupported = $unsupportedKeys
        }
    }
    elseif ($Operation -eq 'EnsureAttribute') {
        if ([string]::IsNullOrWhiteSpace($AttributeName)) {
            throw "AD Provider: AttributeName is required for EnsureAttribute validation."
        }

        $supportedKeys = @($contract.Keys)

        if ($AttributeName -notin $supportedKeys) {
            $errorMessage = "AD Provider: Unsupported attribute in EnsureAttribute operation.`n"
            $errorMessage += "Attribute: $AttributeName`n`n"
            $errorMessage += "Supported attributes for EnsureAttribute:`n"
            $errorMessage += "  - Name: GivenName, Surname, DisplayName`n"
            $errorMessage += "  - Organization: Description, Department, Title`n"
            $errorMessage += "  - Contact: EmailAddress`n"
            $errorMessage += "  - Identity: UserPrincipalName`n"
            $errorMessage += "  - Relationship: Manager`n`n"
            $errorMessage += "Note: Custom LDAP attributes are not supported in EnsureAttribute.`n"
            $errorMessage += "For custom attributes, use CreateIdentity with OtherAttributes or direct provider methods."

            throw $errorMessage
        }

        return @{
            Requested   = @($AttributeName)
            Supported   = @($AttributeName)
            Unsupported = @()
        }
    }
}

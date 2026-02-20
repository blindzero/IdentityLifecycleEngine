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
            
            # Generate supported attributes list from contract
            $supportedAttributesList = ($supportedKeys | Sort-Object | ForEach-Object { "  - $_" }) -join "`n"
            $errorMessage += "$supportedAttributesList`n`n"
            
            if ('OtherAttributes' -in $supportedKeys) {
                $errorMessage += "To set custom LDAP attributes, use the 'OtherAttributes' container."
            }

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

        # Named attributes (have explicit Set-ADUser parameter bindings)
        $namedKeys = @($contract.Keys | Where-Object { -not $_.StartsWith('_') })

        # CreateIdentity-only attributes that must not be used in EnsureAttribute
        $blockedAttributes = @()
        if ($contract.ContainsKey('_BlockedAttributes')) {
            $blockedAttributes = $contract['_BlockedAttributes'].Values
        }

        if ($AttributeName -in $blockedAttributes) {
            $errorMessage = "AD Provider: Unsupported attribute in EnsureAttribute operation.`n"
            $errorMessage += "Attribute: $AttributeName`n`n"
            $errorMessage += "This attribute is only supported in CreateIdentity, not in EnsureAttribute.`n`n"
            $errorMessage += "Named attributes supported for EnsureAttribute:`n"

            $supportedAttributesList = ($namedKeys | Sort-Object | ForEach-Object { "  - $_" }) -join "`n"
            $errorMessage += "$supportedAttributesList`n`n"

            $errorMessage += "Custom LDAP attributes (e.g., mobile, telephoneNumber) are also accepted`n"
            $errorMessage += "and are routed via Set-ADUser -Replace (set value) or -Clear (null value)."

            throw $errorMessage
        }

        # Attribute is either a named parameter or a custom LDAP attribute - both are allowed
        return @{
            Requested   = @($AttributeName)
            Supported   = @($AttributeName)
            Unsupported = @()
        }
    }
}

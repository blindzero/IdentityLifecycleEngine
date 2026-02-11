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

        $supportedKeys = @($contract.Keys)

        if ($AttributeName -notin $supportedKeys) {
            $errorMessage = "AD Provider: Unsupported attribute in EnsureAttribute operation.`n"
            $errorMessage += "Attribute: $AttributeName`n`n"
            $errorMessage += "Supported attributes for EnsureAttribute:`n"
            
            # Generate supported attributes list from contract
            $supportedAttributesList = ($supportedKeys | Sort-Object | ForEach-Object { "  - $_" }) -join "`n"
            $errorMessage += "$supportedAttributesList`n`n"
            
            $errorMessage += "Note: Custom LDAP attributes and password attributes are not supported in EnsureAttribute.`n"
            $errorMessage += "For custom attributes, use CreateIdentity with OtherAttributes."

            throw $errorMessage
        }

        return @{
            Requested   = @($AttributeName)
            Supported   = @($AttributeName)
            Unsupported = @()
        }
    }
}

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
    The operation context: 'CreateIdentity' or 'EnsureAttributes'.

    .PARAMETER AttributeName
    For EnsureAttributes, the specific attribute name being set.

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
    $result = Test-IdleADAttributeContract -Operation 'EnsureAttributes' -AttributeName 'MobilePhone'
    # Throws if attribute not supported for EnsureAttributes
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter()]
        [AllowNull()]
        [hashtable] $Attributes,

        [Parameter(Mandatory)]
        [ValidateSet('CreateIdentity', 'EnsureAttributes')]
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
    elseif ($Operation -eq 'EnsureAttributes') {
        if ([string]::IsNullOrWhiteSpace($AttributeName)) {
            throw "AD Provider: AttributeName is required for EnsureAttributes validation."
        }

        # OtherAttributes is a valid container key in EnsureAttributes
        if ($AttributeName -eq 'OtherAttributes') {
            return @{
                Requested   = @($AttributeName)
                Supported   = @($AttributeName)
                Unsupported = @()
            }
        }

        $supportedKeys = @($contract.Keys)

        if ($AttributeName -notin $supportedKeys) {
            $errorMessage = "AD Provider: Unsupported attribute in EnsureAttributes operation.`n"
            $errorMessage += "Attribute: $AttributeName`n`n"
            $errorMessage += "Supported attributes for EnsureAttributes:`n"
            
            # Generate supported attributes list from contract (exclude OtherAttributes container)
            $namedKeys = @($supportedKeys | Where-Object { $_ -ne 'OtherAttributes' })
            $supportedAttributesList = ($namedKeys | Sort-Object | ForEach-Object { "  - $_" }) -join "`n"
            $errorMessage += "$supportedAttributesList`n`n"
            
            $errorMessage += "Note: For custom LDAP attributes not listed above, use the 'OtherAttributes' container`n"
            $errorMessage += "with valid LDAP attribute names as keys (e.g. OtherAttributes = @{ mobile = `$null })."

            throw $errorMessage
        }

        return @{
            Requested   = @($AttributeName)
            Supported   = @($AttributeName)
            Unsupported = @()
        }
    }
}

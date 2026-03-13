function Get-IdleEntraIDGraphResponseProperty {
    <#
    .SYNOPSIS
    Safely reads a named property from a Microsoft Graph API response object.

    .DESCRIPTION
    Handles both PSCustomObject and IDictionary/hashtable response shapes from the
    Microsoft Graph PowerShell module. Returns $null when the property is absent or
    when any error occurs reading it, so callers never throw on missing response fields.

    .PARAMETER InputObject
    The response object returned by the Graph API. May be $null, a PSCustomObject,
    or a hashtable/IDictionary.

    .PARAMETER PropertyName
    The name of the property to read (e.g. 'value', '@odata.nextLink').

    .OUTPUTS
    The property value, or $null when the property is absent, the input is $null,
    or an error occurs.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter()]
        [object] $InputObject,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $PropertyName
    )

    if ($null -eq $InputObject) {
        return $null
    }

    try {
        if ($InputObject -is [System.Collections.IDictionary]) {
            if ($InputObject.Contains($PropertyName)) {
                return $InputObject[$PropertyName]
            }
            return $null
        }

        # PSCustomObject / general object — use PSObject.Properties to avoid strict-mode throw
        $prop = $InputObject.PSObject.Properties[$PropertyName]
        if ($null -ne $prop) {
            return $prop.Value
        }
        return $null
    }
    catch {
        Write-Verbose "Get-IdleEntraIDGraphResponseProperty: error reading '$PropertyName': $_"
        return $null
    }
}

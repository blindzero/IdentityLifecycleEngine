Set-StrictMode -Version Latest

function ConvertTo-IdleADEntitlement {
    <#
    .SYNOPSIS
    Converts a value to an IdLE.Entitlement object for AD provider.

    .DESCRIPTION
    Normalizes and validates entitlement values from various input formats
    (hashtable, PSCustomObject) into a standard IdLE.Entitlement object.

    The function validates that required fields (Kind, Id) are present and not empty.

    .PARAMETER Value
    The input value to convert. Can be a hashtable or PSCustomObject with
    Kind and Id properties.

    .OUTPUTS
    PSCustomObject with PSTypeName 'IdLE.Entitlement'
    - PSTypeName: 'IdLE.Entitlement'
    - Kind: Entitlement kind (e.g., 'Group')
    - Id: Entitlement identifier (e.g., Group DN)

    .EXAMPLE
    $ent = ConvertTo-IdleADEntitlement -Value @{ Kind = 'Group'; Id = 'CN=MyGroup,OU=Groups,DC=contoso,DC=com' }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Value
    )

    $kind = $null
    $id = $null

    if ($Value -is [System.Collections.IDictionary]) {
        $kind = $Value['Kind']
        $id = $Value['Id']
    }
    else {
        $props = $Value.PSObject.Properties
        if ($props.Name -contains 'Kind') { $kind = $Value.Kind }
        if ($props.Name -contains 'Id') { $id = $Value.Id }
    }

    if ([string]::IsNullOrWhiteSpace([string]$kind)) {
        throw "Entitlement.Kind must not be empty."
    }
    if ([string]::IsNullOrWhiteSpace([string]$id)) {
        throw "Entitlement.Id must not be empty."
    }

    return [pscustomobject]@{
        PSTypeName = 'IdLE.Entitlement'
        Kind       = [string]$kind
        Id         = [string]$id
    }
}

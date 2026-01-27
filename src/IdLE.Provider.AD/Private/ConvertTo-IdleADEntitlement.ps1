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
    Kind, Id, and optionally DisplayName properties.

    .OUTPUTS
    PSCustomObject with PSTypeName 'IdLE.Entitlement'
    - PSTypeName: 'IdLE.Entitlement'
    - Kind: Entitlement kind (e.g., 'Group')
    - Id: Entitlement identifier (e.g., Group DN)
    - DisplayName: Optional display name (null if not provided or empty)

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
    $displayName = $null

    if ($Value -is [System.Collections.IDictionary]) {
        $kind = $Value['Kind']
        $id = $Value['Id']
        if ($Value.Contains('DisplayName')) { $displayName = $Value['DisplayName'] }
    }
    else {
        $props = $Value.PSObject.Properties
        if ($props.Name -contains 'Kind') { $kind = $Value.Kind }
        if ($props.Name -contains 'Id') { $id = $Value.Id }
        if ($props.Name -contains 'DisplayName') { $displayName = $Value.DisplayName }
    }

    if ([string]::IsNullOrWhiteSpace([string]$kind)) {
        throw "Entitlement.Kind must not be empty."
    }
    if ([string]::IsNullOrWhiteSpace([string]$id)) {
        throw "Entitlement.Id must not be empty."
    }

    return [pscustomobject]@{
        PSTypeName  = 'IdLE.Entitlement'
        Kind        = [string]$kind
        Id          = [string]$id
        DisplayName = if ($null -eq $displayName -or [string]::IsNullOrWhiteSpace([string]$displayName)) {
            $null
        }
        else {
            [string]$displayName
        }
    }
}

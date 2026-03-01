function ConvertTo-IdlePruneEntitlement {
    # Converts a raw hashtable or object Keep entry into a normalized pscustomobject with Kind, Id and optional DisplayName.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Value,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $DefaultKind
    )

    $kind = $null
    $id = $null
    $displayName = $null

    if ($Value -is [System.Collections.IDictionary]) {
        if ($Value.Contains('Kind')) { $kind = $Value['Kind'] }
        if ($Value.Contains('Id')) { $id = $Value['Id'] }
        if ($Value.Contains('DisplayName')) { $displayName = $Value['DisplayName'] }
    }
    else {
        $props = $Value.PSObject.Properties
        if ($props.Name -contains 'Kind') { $kind = $Value.Kind }
        if ($props.Name -contains 'Id') { $id = $Value.Id }
        if ($props.Name -contains 'DisplayName') { $displayName = $Value.DisplayName }
    }

    if ([string]::IsNullOrWhiteSpace([string]$kind)) {
        $kind = $DefaultKind
    }

    if ([string]::IsNullOrWhiteSpace([string]$id)) {
        throw "PruneEntitlements: each Keep entry requires an Id."
    }

    $normalized = [ordered]@{
        Kind = [string]$kind
        Id   = [string]$id
    }

    if ($null -ne $displayName -and -not [string]::IsNullOrWhiteSpace([string]$displayName)) {
        $normalized['DisplayName'] = [string]$displayName
    }

    return [pscustomobject]$normalized
}

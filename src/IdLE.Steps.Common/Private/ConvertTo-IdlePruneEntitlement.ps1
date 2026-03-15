function ConvertTo-IdlePruneEntitlement {
    # Converts a raw hashtable or object Keep entry into a normalized pscustomobject with Kind and Id.
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

    if ($Value -is [System.Collections.IDictionary]) {
        if ($Value.Contains('Kind')) { $kind = $Value['Kind'] }
        if ($Value.Contains('Id')) { $id = $Value['Id'] }
    }
    else {
        $props = $Value.PSObject.Properties
        if ($props.Name -contains 'Kind') { $kind = $Value.Kind }
        if ($props.Name -contains 'Id') { $id = $Value.Id }
    }

    if ([string]::IsNullOrWhiteSpace([string]$kind)) {
        $kind = $DefaultKind
    }

    if ([string]::IsNullOrWhiteSpace([string]$id)) {
        throw "PruneEntitlements: each Keep entry requires an Id."
    }

    return [pscustomobject]@{
        Kind = [string]$kind
        Id   = [string]$id
    }
}

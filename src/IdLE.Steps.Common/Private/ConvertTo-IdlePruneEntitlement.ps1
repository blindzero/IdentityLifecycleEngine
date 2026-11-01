function ConvertTo-IdlePruneEntitlement {
    # Converts a raw hashtable or object Keep entry into a normalized pscustomobject with Kind and Id.
    # Keep entries inherit the prune scope (With.Kind); an explicit Kind must match it, because a Keep
    # entry of another Kind could neither protect nor (for EnsureKeep) be granted within this scope.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Value,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Kind
    )

    $entryKind = $null
    $id = $null

    if ($Value -is [System.Collections.IDictionary]) {
        if ($Value.Contains('Kind')) { $entryKind = $Value['Kind'] }
        if ($Value.Contains('Id')) { $id = $Value['Id'] }
    }
    else {
        $props = $Value.PSObject.Properties
        if ($props.Name -contains 'Kind') { $entryKind = $Value.Kind }
        if ($props.Name -contains 'Id') { $id = $Value.Id }
    }

    if ([string]::IsNullOrWhiteSpace([string]$id)) {
        throw "PruneEntitlements: each Keep entry requires an Id."
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$entryKind) -and
        -not [string]::Equals([string]$entryKind, $Kind, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "PruneEntitlements: Keep entry '$id' has Kind '$entryKind', but the step prunes Kind '$Kind'. Use one prune step per Kind."
    }

    return [pscustomobject]@{
        Kind = $Kind
        Id   = [string]$id
    }
}

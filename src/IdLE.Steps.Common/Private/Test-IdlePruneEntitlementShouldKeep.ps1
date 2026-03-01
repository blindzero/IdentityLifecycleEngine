function Test-IdlePruneEntitlementShouldKeep {
    # Returns $true if the given entitlement should be kept based on explicit Keep items or KeepPattern wildcards.
    # Used by both IdLE.Step.PruneEntitlements and IdLE.Step.PruneEntitlementsEnsureKeep.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Ent,

        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]] $KeepItems,

        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [string[]] $KeepPatterns
    )

    # Check explicit Keep items (case-insensitive Id match)
    foreach ($k in $KeepItems) {
        if ([string]::Equals([string]$Ent.Id, [string]$k.Id, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }

    # Check KeepPattern (wildcard -like against Id and DisplayName)
    foreach ($pattern in $KeepPatterns) {
        if ([string]$Ent.Id -like $pattern) { return $true }
        if ($Ent.PSObject.Properties.Name -contains 'DisplayName' -and
            $null -ne $Ent.DisplayName -and
            [string]$Ent.DisplayName -like $pattern) { return $true }
    }

    return $false
}

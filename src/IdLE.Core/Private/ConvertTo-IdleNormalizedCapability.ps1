Set-StrictMode -Version Latest

function ConvertTo-IdleNormalizedCapability {
    <#
    .SYNOPSIS
    Normalizes capability identifiers and maps deprecated IDs to current ones.

    .DESCRIPTION
    Handles capability ID migrations and deprecation warnings during planning.
    Pre-1.0 deprecated capability IDs are mapped to their replacements and emit a warning.

    .PARAMETER Capability
    The raw capability identifier to normalize.

    .OUTPUTS
    Normalized capability identifier (string).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Capability
    )

    # Deprecated capability ID mappings (pre-1.0)
    # Format: @{ 'OldID' = 'NewID' }
    $deprecatedMappings = @{
        'IdLE.Mailbox.Read' = 'IdLE.Mailbox.Info.Read'
    }

    $normalized = $Capability.Trim()

    if ($deprecatedMappings.ContainsKey($normalized)) {
        $newId = $deprecatedMappings[$normalized]
        Write-Warning "DEPRECATED: Capability '$normalized' is deprecated in v1.0 and will be removed in v2.0. Use '$newId' instead."
        return $newId
    }

    return $normalized
}

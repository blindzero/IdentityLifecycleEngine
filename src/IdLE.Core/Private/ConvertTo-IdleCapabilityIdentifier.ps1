Set-StrictMode -Version Latest

function ConvertTo-IdleCapabilityIdentifier {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object] $Value
    )

    if ($null -eq $Value) {
        return $null
    }

    $cap = ($Value -as [string]).Trim()
    if ([string]::IsNullOrWhiteSpace($cap)) {
        return $null
    }

    return $cap
}

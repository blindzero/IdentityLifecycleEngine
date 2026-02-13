Set-StrictMode -Version Latest

function ConvertTo-NullIfEmptyString {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object] $Value
    )

    if ($null -eq $Value) {
        return $null
    }

    if ($Value -is [string] -and [string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }

    return $Value
}

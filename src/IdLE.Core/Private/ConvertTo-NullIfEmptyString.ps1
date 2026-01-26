Set-StrictMode -Version Latest

function ConvertTo-NullIfEmptyString {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [string] $Value
    )

    if ($null -eq $Value) {
        return $null
    }

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }

    return $Value
}

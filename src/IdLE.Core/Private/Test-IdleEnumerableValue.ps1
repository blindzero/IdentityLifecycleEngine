Set-StrictMode -Version Latest

function Test-IdleEnumerableValue {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object] $Value
    )

    if ($null -eq $Value) {
        return $false
    }

    return ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string]))
}

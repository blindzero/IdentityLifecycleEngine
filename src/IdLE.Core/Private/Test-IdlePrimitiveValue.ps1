Set-StrictMode -Version Latest

function Test-IdlePrimitiveValue {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object] $Value
    )

    if ($null -eq $Value) {
        return $false
    }

    return ($Value -is [string] -or
        $Value -is [int] -or
        $Value -is [long] -or
        $Value -is [double] -or
        $Value -is [decimal] -or
        $Value -is [bool] -or
        $Value -is [datetime] -or
        $Value -is [guid])
}

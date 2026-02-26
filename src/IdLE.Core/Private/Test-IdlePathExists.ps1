Set-StrictMode -Version Latest

function Test-IdlePathExists {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [object] $Object,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Path
    )

    $current = $Object
    foreach ($segment in ($Path -split '\.')) {
        if ($null -eq $current) {
            return $false
        }

        if ($current -is [System.Collections.IDictionary]) {
            if (-not $current.Contains($segment)) {
                return $false
            }

            $current = $current[$segment]
            continue
        }

        $prop = $current.PSObject.Properties[$segment]
        if ($null -eq $prop) {
            return $false
        }

        $current = $prop.Value
    }

    return $true
}

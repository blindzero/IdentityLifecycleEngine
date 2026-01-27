Set-StrictMode -Version Latest

function Get-IdleProvidersFromMap {
    <#
    .SYNOPSIS
    Extracts provider instances from the -Providers argument.

    .DESCRIPTION
    Supports both:
    - hashtable map: @{ Name = <providerObject>; ... }
    - array/list: @( <providerObject>, ... )

    Returns an array of provider objects.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object] $Providers
    )

    if ($null -eq $Providers) {
        return @()
    }

    if ($Providers -is [System.Collections.IDictionary]) {
        $items = @()
        foreach ($k in $Providers.Keys) {
            $items += $Providers[$k]
        }
        return @($items)
    }

    if ($Providers -is [System.Collections.IEnumerable] -and $Providers -isnot [string]) {
        $items = @()
        foreach ($p in $Providers) {
            $items += $p
        }
        return @($items)
    }

    return @($Providers)
}

Set-StrictMode -Version Latest

function Get-IdleOptionalPropertyValue {
    <#
    .SYNOPSIS
    Safely reads an optional property from an object.

    .DESCRIPTION
    Works with:
    - IDictionary (hashtables / ordered dictionaries)
    - PSCustomObject / objects with note properties

    Returns $null when the property does not exist.
    Uses Get-Member to avoid PropertyNotFoundException in strict mode.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [object] $Object,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Name
    )

    if ($null -eq $Object) {
        return $null
    }

    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.ContainsKey($Name)) {
            return $Object[$Name]
        }
        return $null
    }

    $m = $Object | Get-Member -Name $Name -MemberType NoteProperty, Property -ErrorAction SilentlyContinue
    if ($null -eq $m) {
        return $null
    }

    return $Object.$Name
}

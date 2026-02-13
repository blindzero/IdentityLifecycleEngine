function Copy-IdleDataObject {
    <#
    .SYNOPSIS
    Creates a deep-ish, data-only copy of an object.

    .DESCRIPTION
    This helper is used to snapshot data-like objects so that exported or executed
    artifacts do not retain references to caller-owned objects.

    NOTE:
    This is intentionally conservative and only supports data-like objects:
    - Hashtable / OrderedDictionary
    - PSCustomObject / NoteProperties
    - Arrays/lists
    - Primitive types

    ScriptBlocks and other executable objects are rejected by upstream validation.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object] $Value
    )

    if ($null -eq $Value) { return $null }

    # Primitive / immutable types should be returned as-is before property inspection.
    # This prevents strings from being converted to PSCustomObject with Length property.
    if (Test-IdlePrimitiveValue -Value $Value) {
        return $Value
    }

    if ($Value -is [System.Collections.IDictionary]) {
        $copy = @{}
        foreach ($k in $Value.Keys) {
            $copy[$k] = Copy-IdleDataObject -Value $Value[$k]
        }
        return $copy
    }

    if (Test-IdleEnumerableValue -Value $Value) {
        $arr = @()
        foreach ($item in $Value) {
            $arr += Copy-IdleDataObject -Value $item
        }
        return $arr
    }

    $props = @($Value.PSObject.Properties | Where-Object MemberType -in @('NoteProperty', 'Property'))
    if ($null -ne $props -and @($props).Count -gt 0) {
        $o = [ordered]@{}
        foreach ($p in $props) {
            $o[$p.Name] = Copy-IdleDataObject -Value $p.Value
        }
        return [pscustomobject]$o
    }

    return $Value
}

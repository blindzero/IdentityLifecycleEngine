# Asserts that the provided value does not contain any ScriptBlock objects.
# Recursively walks hashtables, enumerables, and PSCustomObjects.

function Assert-IdleNoScriptBlock {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [object] $Value,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Path
    )

    if ($null -eq $Value) { return }

    if ($Value -is [scriptblock]) {
        throw [System.ArgumentException]::new("ScriptBlocks are not allowed in request data. Found at: $Path", $Path)
    }

    # Hashtable / Dictionary
    if ($Value -is [System.Collections.IDictionary]) {
        foreach ($key in $Value.Keys) {
            Assert-IdleNoScriptBlock -Value $Value[$key] -Path "$Path.$key"
        }
        return
    }

    # Enumerable (but not string)
    if (($Value -is [System.Collections.IEnumerable]) -and ($Value -isnot [string])) {
        $i = 0
        foreach ($item in $Value) {
            Assert-IdleNoScriptBlock -Value $item -Path "$Path[$i]"
            $i++
        }
        return
    }

    # PSCustomObject (walk note properties)
    if ($Value -is [psobject]) {
        foreach ($p in $Value.PSObject.Properties) {
            if ($p.MemberType -eq 'NoteProperty') {
                Assert-IdleNoScriptBlock -Value $p.Value -Path "$Path.$($p.Name)"
            }
        }
    }
}

# Asserts that the provided InputObject does not contain any ScriptBlock objects.
# Recursively walks hashtables, enumerables, and PSCustomObjects.

function Assert-IdleNoScriptBlock {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [object] $InputObject,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Path
    )

    if ($null -eq $InputObject) { return }

    if ($InputObject -is [scriptblock]) {
        throw [System.ArgumentException]::new(
            "ScriptBlocks are not allowed in request data. Found at: $Path",
            $Path
        )
    }

    # Hashtable / Dictionary
    if ($InputObject -is [System.Collections.IDictionary]) {
        foreach ($key in $InputObject.Keys) {
            Assert-IdleNoScriptBlock -InputObject $InputObject[$key] -Path "$Path.$key"
        }
        return
    }

    # Enumerable (but not string)
    if (($InputObject -is [System.Collections.IEnumerable]) -and ($InputObject -isnot [string])) {
        $i = 0
        foreach ($item in $InputObject) {
            Assert-IdleNoScriptBlock -InputObject $item -Path "$Path[$i]"
            $i++
        }
        return
    }

    # PSCustomObject (walk note properties)
    if ($InputObject -is [pscustomobject]) {
        foreach ($p in $InputObject.PSObject.Properties) {
            if ($p.MemberType -eq 'NoteProperty') {
                # PSPropertyInfo does not expose "InputObject" here; the value is in .Value.
                Assert-IdleNoScriptBlock -InputObject $p.Value -Path "$Path.$($p.Name)"
            }
        }
    }
}

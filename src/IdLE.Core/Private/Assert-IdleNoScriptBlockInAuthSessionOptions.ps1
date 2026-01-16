# Validates that auth session options do not contain ScriptBlock objects.
# Recursively walks hashtables, enumerables, and PSCustomObjects.
# Enforces the security boundary: auth session options must be data-only.

function Assert-IdleNoScriptBlockInAuthSessionOptions {
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
            "ScriptBlocks are not allowed in auth session options. Found at: $Path",
            $Path
        )
    }

    if ($InputObject -is [System.Collections.IDictionary]) {
        foreach ($key in $InputObject.Keys) {
            Assert-IdleNoScriptBlockInAuthSessionOptions -InputObject $InputObject[$key] -Path "$Path.$key"
        }
        return
    }

    if (($InputObject -is [System.Collections.IEnumerable]) -and ($InputObject -isnot [string])) {
        $i = 0
        foreach ($item in $InputObject) {
            Assert-IdleNoScriptBlockInAuthSessionOptions -InputObject $item -Path "$Path[$i]"
            $i++
        }
        return
    }

    if ($InputObject -is [pscustomobject]) {
        foreach ($p in $InputObject.PSObject.Properties) {
            if ($p.MemberType -eq 'NoteProperty') {
                Assert-IdleNoScriptBlockInAuthSessionOptions -InputObject $p.Value -Path "$Path.$($p.Name)"
            }
        }
    }
}

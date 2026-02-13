function Assert-IdleNoScriptBlock {
    <#
    .SYNOPSIS
    Asserts that the provided object does not contain any ScriptBlock objects.

    .DESCRIPTION
    This is a security-critical helper that validates data-only constraints.
    It recursively walks hashtables, enumerables, and PSCustomObjects to ensure
    no ScriptBlock objects are present.

    This helper enforces IdLE's security boundary: workflow configuration and step inputs
    must not contain executable code.

    Step implementations should use this helper to validate their inputs rather than
    implementing custom ScriptBlock checks.

    .PARAMETER InputObject
    The object to validate. Can be null, a scalar value, or a complex nested structure.

    .PARAMETER Path
    The logical path describing the current position in the data structure.
    Used in error messages to pinpoint where a ScriptBlock was found.

    .OUTPUTS
    None. Throws an ArgumentException if a ScriptBlock is found.

    .EXAMPLE
    # Validate a hashtable
    $config = @{
        Mode = 'Enabled'
        Message = 'Out of office'
    }
    Assert-IdleNoScriptBlock -InputObject $config -Path 'With.Config'

    .EXAMPLE
    # Detect ScriptBlock in nested structure
    $data = @{
        Setting = { Write-Host "bad" }
    }
    Assert-IdleNoScriptBlock -InputObject $data -Path 'Input'
    # Throws: ScriptBlocks are not allowed in request data. Found at: Input.Setting
    #>
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

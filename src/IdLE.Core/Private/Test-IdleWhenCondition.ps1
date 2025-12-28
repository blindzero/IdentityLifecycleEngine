function Test-IdleWhenCondition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable] $When,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Context
    )

    # Minimal declarative condition schema:
    # - Path (string) required
    # - Exactly one of: Equals, NotEquals, Exists
    if (-not $When.ContainsKey('Path') -or [string]::IsNullOrWhiteSpace([string]$When.Path)) {
        throw [System.ArgumentException]::new("When condition requires key 'Path'.", 'When')
    }

    $ops = @('Equals', 'NotEquals', 'Exists')
    $presentOps = @($ops | Where-Object { $When.ContainsKey($_) })
    if ($presentOps.Count -ne 1) {
        throw [System.ArgumentException]::new("When condition must specify exactly one operator: Equals, NotEquals, Exists.", 'When')
    }

    $value = Get-IdleValueByPath -Object $Context -Path ([string]$When.Path)

    if ($When.ContainsKey('Exists')) {
        $expected = [bool]$When.Exists
        $actual = ($null -ne $value)
        return ($actual -eq $expected)
    }

    if ($When.ContainsKey('Equals')) {
        return ([string]$value -eq [string]$When.Equals)
    }

    if ($When.ContainsKey('NotEquals')) {
        return ([string]$value -ne [string]$When.NotEquals)
    }

    # Should never reach here due to validation.
    return $false
}

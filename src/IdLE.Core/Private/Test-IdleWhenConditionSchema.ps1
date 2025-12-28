function Test-IdleWhenConditionSchema {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable] $When,

        [Parameter()]
        [AllowNull()]
        [string] $StepName
    )

    $errors = [System.Collections.Generic.List[string]]::new()
    $prefix = if ([string]::IsNullOrWhiteSpace($StepName)) { 'Step' } else { "Step '$StepName'" }

    if (-not $When.ContainsKey('Path') -or [string]::IsNullOrWhiteSpace([string]$When.Path)) {
        $errors.Add("$($prefix): When requires key 'Path' with a non-empty string value.")
        return $errors
    }

    # Exactly one operator allowed (MVP)
    $ops = @('Equals', 'NotEquals', 'Exists')
    $presentOps = @($ops | Where-Object { $When.ContainsKey($_) })

    if ($presentOps.Count -ne 1) {
        $errors.Add("$($prefix): When must specify exactly one operator: Equals, NotEquals, Exists.")
        return $errors
    }

    # Exists must be boolean-like
    if ($When.ContainsKey('Exists')) {
        try { [void][bool]$When.Exists } catch { $errors.Add("$($prefix): When.Exists must be boolean.") }
    }

    return $errors
}

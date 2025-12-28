function Test-IdleStepDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Step,

        [Parameter(Mandatory)]
        [ValidateRange(0, 1000000)]
        [int] $Index
    )

    $errors = [System.Collections.Generic.List[string]]::new()

    # Step must be a dictionary-like object (workflow steps are data)
    if (-not ($Step -is [System.Collections.IDictionary])) {
        $errors.Add("Step[$Index]: Step must be a hashtable/dictionary.")
        return $errors
    }

    $name = if ($Step.Contains('Name')) { [string]$Step['Name'] } else { $null }
    $type = if ($Step.Contains('Type')) { [string]$Step['Type'] } else { $null }

    if ([string]::IsNullOrWhiteSpace($name)) { $errors.Add("Step[$Index]: Missing or empty 'Name'.") }
    if ([string]::IsNullOrWhiteSpace($type)) { $errors.Add("Step[$Index] ($name): Missing or empty 'Type'.") }

    # Enforce data-only: no ScriptBlock anywhere inside the step definition
    # (Reuse your existing helper if available)
    try {
        Assert-IdleNoScriptBlock -InputObject $Step -Path ("Step[$Index] ($name)")
    }
    catch {
        $errors.Add($_.Exception.Message)
    }

    # Validate With (if present)
    if ($Step.Contains('With') -and $null -ne $Step['With']) {
        if (-not ($Step['With'] -is [System.Collections.IDictionary])) {
            $errors.Add("Step[$Index] ($name): 'With' must be a hashtable/dictionary when provided.")
        }
    }

    # Validate When schema (if present)
    if ($Step.Contains('When') -and $null -ne $Step['When']) {
        if (-not ($Step['When'] -is [hashtable])) {
            $errors.Add("Step[$Index] ($name): 'When' must be a hashtable when provided.")
        }
        else {
            foreach ($e in (Test-IdleWhenConditionSchema -When $Step['When'] -StepName $name)) {
                $errors.Add($e)
            }
        }
    }

    return $errors
}

function Test-IdleWorkflowSchema {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Workflow
    )

    # Strict validation: collect all schema violations and return them as a list.
    $errors = [System.Collections.Generic.List[string]]::new()

    $allowedRootKeys = @('Name', 'LifecycleEvent', 'Steps', 'OnFailureSteps', 'Description')
    foreach ($key in $Workflow.Keys) {
        if ($allowedRootKeys -notcontains $key) {
            $errors.Add("Unknown root key '$key'. Allowed keys: $($allowedRootKeys -join ', ').")
        }
    }

    if (-not $Workflow.ContainsKey('Name') -or [string]::IsNullOrWhiteSpace([string]$Workflow.Name)) {
        $errors.Add("Missing or empty required root key 'Name'.")
    }

    if (-not $Workflow.ContainsKey('LifecycleEvent') -or [string]::IsNullOrWhiteSpace([string]$Workflow.LifecycleEvent)) {
        $errors.Add("Missing or empty required root key 'LifecycleEvent'.")
    }

    if (-not $Workflow.ContainsKey('Steps') -or $null -eq $Workflow.Steps) {
        $errors.Add("Missing required root key 'Steps'.")
    }
    elseif ($Workflow.Steps -isnot [System.Collections.IEnumerable] -or $Workflow.Steps -is [string]) {
        $errors.Add("'Steps' must be an array/list of step hashtables.")
    }
    else {
        $stepNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

        $i = 0
        foreach ($step in $Workflow.Steps) {
            $stepPath = "Steps[$i]"

            if ($null -eq $step -or $step -isnot [hashtable]) {
                $errors.Add("$stepPath must be a hashtable.")
                $i++
                continue
            }

            $allowedStepKeys = @('Name', 'Type', 'Condition', 'With', 'Description', 'RequiresCapabilities')
            foreach ($k in $step.Keys) {
                if ($allowedStepKeys -notcontains $k) {
                    $errors.Add("Unknown key '$k' in $stepPath. Allowed keys: $($allowedStepKeys -join ', ').")
                }
            }

            if (-not $step.ContainsKey('Name') -or [string]::IsNullOrWhiteSpace([string]$step.Name)) {
                $errors.Add("Missing or empty required key '$stepPath.Name'.")
            }
            else {
                if (-not $stepNames.Add([string]$step.Name)) {
                    $errors.Add("Duplicate step name '$($step.Name)' detected. Step names must be unique.")
                }
            }

            if (-not $step.ContainsKey('Type') -or [string]::IsNullOrWhiteSpace([string]$step.Type)) {
                $errors.Add("Missing or empty required key '$stepPath.Type'.")
            }

            # Conditions must be declarative data, never a ScriptBlock/expression.
            # We only enforce the shape here; semantic validation comes later.
            if ($step.ContainsKey('Condition') -and $null -ne $step.Condition -and $step.Condition -isnot [hashtable]) {
                $errors.Add("'$stepPath.Condition' must be a hashtable (declarative condition object).")
            }

            # 'With' is step parameter bag (data-only). Detailed validation comes with step metadata later.
            if ($step.ContainsKey('With') -and $null -ne $step.With -and $step.With -isnot [hashtable]) {
                $errors.Add("'$stepPath.With' must be a hashtable (step parameters).")
            }

            $i++
        }
    }

    # OnFailureSteps are optional. If present, validate them like regular Steps.
    if ($Workflow.ContainsKey('OnFailureSteps') -and $null -ne $Workflow.OnFailureSteps) {
        if ($Workflow.OnFailureSteps -isnot [System.Collections.IEnumerable] -or $Workflow.OnFailureSteps -is [string]) {
            $errors.Add("'OnFailureSteps' must be an array/list of step hashtables.")
        }
        else {
            $stepNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

            $i = 0
            foreach ($step in $Workflow.OnFailureSteps) {
                $stepPath = "OnFailureSteps[$i]"

                if ($null -eq $step -or $step -isnot [hashtable]) {
                    $errors.Add("$stepPath must be a hashtable.")
                    $i++
                    continue
                }

                $allowedStepKeys = @('Name', 'Type', 'Condition', 'With', 'Description', 'RequiresCapabilities')
                foreach ($k in $step.Keys) {
                    if ($allowedStepKeys -notcontains $k) {
                        $errors.Add("Unknown key '$k' in $stepPath. Allowed keys: $($allowedStepKeys -join ', ').")
                    }
                }

                if (-not $step.ContainsKey('Name') -or [string]::IsNullOrWhiteSpace([string]$step.Name)) {
                    $errors.Add("Missing or empty required key '$stepPath.Name'.")
                }
                else {
                    if (-not $stepNames.Add([string]$step.Name)) {
                        $errors.Add("Duplicate step name '$($step.Name)' detected in 'OnFailureSteps'. Step names must be unique.")
                    }
                }

                if (-not $step.ContainsKey('Type') -or [string]::IsNullOrWhiteSpace([string]$step.Type)) {
                    $errors.Add("Missing or empty required key '$stepPath.Type'.")
                }

                # Conditions must be declarative data, never a ScriptBlock/expression.
                # We only enforce the shape here; semantic validation comes later.
                if ($step.ContainsKey('Condition') -and $null -ne $step.Condition -and $step.Condition -isnot [hashtable]) {
                    $errors.Add("'$stepPath.Condition' must be a hashtable (declarative condition object).")
                }

                # 'With' is step parameter bag (data-only). Detailed validation comes with step metadata later.
                if ($step.ContainsKey('With') -and $null -ne $step.With -and $step.With -isnot [hashtable]) {
                    $errors.Add("'$stepPath.With' must be a hashtable (step parameters).")
                }

                $i++
            }
        }
    }

    return $errors
}

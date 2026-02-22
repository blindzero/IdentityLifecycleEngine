function Test-IdleWorkflowSchema {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Workflow
    )

    # Strict validation: collect all schema violations and return them as a list.
    $errors = [System.Collections.Generic.List[string]]::new()

    # Helper: Validate step keys and detect disallowed keys.
    function Test-IdleWorkflowStepKeys {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [hashtable] $Step,

            [Parameter(Mandatory)]
            [string] $StepPath,

            [Parameter(Mandatory)]
            [AllowEmptyCollection()]
            [System.Collections.Generic.List[string]] $ErrorList
        )

        $allowedStepKeys = @('Name', 'Type', 'Condition', 'With', 'Description', 'RetryProfile', 'Preconditions', 'OnPreconditionFalse', 'PreconditionEvent')
        foreach ($k in $Step.Keys) {
            if ($allowedStepKeys -notcontains $k) {
                $ErrorList.Add("Unknown key '$k' in $StepPath. Allowed keys: $($allowedStepKeys -join ', ').")
            }
        }
    }

    # Helper: Validate RetryProfile property
    function Test-IdleWorkflowStepRetryProfile {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [hashtable] $Step,

            [Parameter(Mandatory)]
            [string] $StepPath,

            [Parameter(Mandatory)]
            [AllowEmptyCollection()]
            [System.Collections.Generic.List[string]] $ErrorList
        )

        if ($Step.ContainsKey('RetryProfile') -and $null -ne $Step.RetryProfile) {
            $retryProfile = [string]$Step.RetryProfile
            if ([string]::IsNullOrWhiteSpace($retryProfile)) {
                $ErrorList.Add("'$StepPath.RetryProfile' must not be an empty string.")
            }
            elseif ($retryProfile -notmatch '^[A-Za-z0-9_.-]{1,64}$') {
                $ErrorList.Add("'$StepPath.RetryProfile' value '$retryProfile' is invalid. Must match pattern: ^[A-Za-z0-9_.-]{1,64}$")
            }
        }
    }

    # Helper: Validate Preconditions, OnPreconditionFalse, and PreconditionEvent fields on a step.
    function Test-IdleWorkflowStepPreconditions {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [hashtable] $Step,

            [Parameter(Mandatory)]
            [string] $StepPath,

            [Parameter(Mandatory)]
            [AllowEmptyCollection()]
            [System.Collections.Generic.List[string]] $ErrorList
        )

        if ($Step.ContainsKey('Preconditions') -and $null -ne $Step.Preconditions) {
            if (-not ($Step.Preconditions -is [System.Collections.IEnumerable]) -or $Step.Preconditions -is [string]) {
                $ErrorList.Add("'$StepPath.Preconditions' must be an array/list of condition hashtables.")
            }
            else {
                $pcIdx = 0
                foreach ($pc in @($Step.Preconditions)) {
                    if ($pc -isnot [hashtable]) {
                        $ErrorList.Add("'$StepPath.Preconditions[$pcIdx]' must be a hashtable (condition node).")
                    }
                    $pcIdx++
                }
            }
        }

        if ($Step.ContainsKey('OnPreconditionFalse') -and $null -ne $Step.OnPreconditionFalse) {
            $opf = [string]$Step.OnPreconditionFalse
            if ($opf -notin @('Blocked', 'Fail')) {
                $ErrorList.Add("'$StepPath.OnPreconditionFalse' must be 'Blocked' or 'Fail'. Got: '$opf'.")
            }
        }

        if ($Step.ContainsKey('PreconditionEvent') -and $null -ne $Step.PreconditionEvent) {
            if ($Step.PreconditionEvent -isnot [hashtable]) {
                $ErrorList.Add("'$StepPath.PreconditionEvent' must be a hashtable.")
            }
            else {
                $pcEvt = $Step.PreconditionEvent
                if (-not $pcEvt.ContainsKey('Type') -or [string]::IsNullOrWhiteSpace([string]$pcEvt.Type)) {
                    $ErrorList.Add("'$StepPath.PreconditionEvent.Type' is required and must be a non-empty string.")
                }
                if (-not $pcEvt.ContainsKey('Message') -or [string]::IsNullOrWhiteSpace([string]$pcEvt.Message)) {
                    $ErrorList.Add("'$StepPath.PreconditionEvent.Message' is required and must be a non-empty string.")
                }
                if ($pcEvt.ContainsKey('Data') -and $null -ne $pcEvt.Data -and $pcEvt.Data -isnot [hashtable]) {
                    $ErrorList.Add("'$StepPath.PreconditionEvent.Data' must be a hashtable when provided.")
                }
            }
        }
    }

    $allowedRootKeys = @('Name', 'LifecycleEvent', 'Steps', 'OnFailureSteps', 'Description', 'ContextResolvers')
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

            Test-IdleWorkflowStepKeys -Step $step -StepPath $stepPath -ErrorList $errors

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

            # Validate RetryProfile
            Test-IdleWorkflowStepRetryProfile -Step $step -StepPath $stepPath -ErrorList $errors

            # Validate Preconditions, OnPreconditionFalse, PreconditionEvent
            Test-IdleWorkflowStepPreconditions -Step $step -StepPath $stepPath -ErrorList $errors

            $i++
        }
    }

    # OnFailureSteps are optional. If present, validate them like regular Steps.
    if ($Workflow.ContainsKey('OnFailureSteps') -and $null -ne $Workflow.OnFailureSteps) {
        if ($Workflow.OnFailureSteps -isnot [System.Collections.IEnumerable] -or $Workflow.OnFailureSteps -is [string]) {
            $errors.Add("'OnFailureSteps' must be an array/list of step hashtables.")
        }
        else {
            $failureStepNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

            $i = 0
            foreach ($step in $Workflow.OnFailureSteps) {
                $stepPath = "OnFailureSteps[$i]"

                if ($null -eq $step -or $step -isnot [hashtable]) {
                    $errors.Add("$stepPath must be a hashtable.")
                    $i++
                    continue
                }

                Test-IdleWorkflowStepKeys -Step $step -StepPath $stepPath -ErrorList $errors

                if (-not $step.ContainsKey('Name') -or [string]::IsNullOrWhiteSpace([string]$step.Name)) {
                    $errors.Add("Missing or empty required key '$stepPath.Name'.")
                }
                else {
                    if (-not $failureStepNames.Add([string]$step.Name)) {
                        $errors.Add("Duplicate step name '$($step.Name)' detected in 'OnFailureSteps'. Step names must be unique within this collection.")
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

                # Validate RetryProfile
                Test-IdleWorkflowStepRetryProfile -Step $step -StepPath $stepPath -ErrorList $errors

                # Validate Preconditions, OnPreconditionFalse, PreconditionEvent
                Test-IdleWorkflowStepPreconditions -Step $step -StepPath $stepPath -ErrorList $errors

                $i++
            }
        }
    }

    # ContextResolvers are optional. If present, validate each resolver entry.
    if ($Workflow.ContainsKey('ContextResolvers') -and $null -ne $Workflow.ContextResolvers) {
        if ($Workflow.ContextResolvers -isnot [System.Collections.IEnumerable] -or
            $Workflow.ContextResolvers -is [string] -or
            $Workflow.ContextResolvers -is [hashtable]) {
            $errors.Add("'ContextResolvers' must be an array/list of resolver hashtables, not a single hashtable.")
        }
        else {
            # 'To' is not user-configurable; each capability has a predefined output path.
            $allowedResolverKeys = @('Capability', 'Provider', 'With')

            $i = 0
            foreach ($resolver in $Workflow.ContextResolvers) {
                $resolverPath = "ContextResolvers[$i]"

                if ($null -eq $resolver -or $resolver -isnot [hashtable]) {
                    $errors.Add("$resolverPath must be a hashtable.")
                    $i++
                    continue
                }

                foreach ($k in $resolver.Keys) {
                    if ($allowedResolverKeys -notcontains $k) {
                        $errors.Add("Unknown key '$k' in $resolverPath. Allowed keys: $($allowedResolverKeys -join ', ').")
                    }
                }

                if (-not $resolver.ContainsKey('Capability') -or [string]::IsNullOrWhiteSpace([string]$resolver.Capability)) {
                    $errors.Add("Missing or empty required key '$resolverPath.Capability'.")
                }

                # 'With' is optional but must be a hashtable if present.
                if ($resolver.ContainsKey('With') -and $null -ne $resolver.With -and $resolver.With -isnot [hashtable]) {
                    $errors.Add("'$resolverPath.With' must be a hashtable (resolver input parameters).")
                }

                # 'Provider' is optional but must be a non-empty string if present.
                if ($resolver.ContainsKey('Provider') -and $null -ne $resolver.Provider -and [string]::IsNullOrWhiteSpace([string]$resolver.Provider)) {
                    $errors.Add("'$resolverPath.Provider' must not be an empty string.")
                }

                $i++
            }
        }
    }

    return $errors
}

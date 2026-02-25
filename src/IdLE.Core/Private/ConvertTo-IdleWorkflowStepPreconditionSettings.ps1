Set-StrictMode -Version Latest

function ConvertTo-IdleWorkflowStepPreconditionSettings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Step,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $StepName
    )

    $normalized = @{
        Preconditions       = $null
        OnPreconditionFalse = $null
        PreconditionEvent   = $null
    }

    # Runtime Preconditions: evaluated at execution time (not planning time).
    # Each precondition uses the same declarative condition DSL as Condition.
    $hasPreconditions = Test-IdleWorkflowStepKey -Step $Step -Key 'Preconditions'
    $hasPrecondition = Test-IdleWorkflowStepKey -Step $Step -Key 'Precondition'

    $rawPreconditions = if ($hasPreconditions) {
        Get-IdlePropertyValue -Object $Step -Name 'Preconditions'
    }
    else {
        $null
    }

    $rawPrecondition = if ($hasPrecondition) {
        Get-IdlePropertyValue -Object $Step -Name 'Precondition'
    }
    else {
        $null
    }

    $hasPreconditionsValue = $null -ne $rawPreconditions
    $hasPreconditionValue = $null -ne $rawPrecondition

    if ($hasPreconditionsValue -and $hasPreconditionValue) {
        throw [System.ArgumentException]::new(
            ("Workflow step '{0}' must not define both 'Preconditions' and deprecated alias 'Precondition'. Use only 'Preconditions'." -f $StepName),
            'Workflow'
        )
    }

    if ($hasPreconditionsValue) {
        $pcList = @($rawPreconditions)
        for ($pcIdx = 0; $pcIdx -lt $pcList.Count; $pcIdx++) {
            $pc = $pcList[$pcIdx]
            if ($pc -isnot [System.Collections.IDictionary]) {
                throw [System.ArgumentException]::new(
                    ("Workflow step '{0}': Preconditions[{1}] must be a hashtable (condition node)." -f $StepName, $pcIdx),
                    'Workflow'
                )
            }

            $pcErrors = Test-IdleConditionSchema -Condition ([hashtable]$pc) -StepName $StepName
            if (@($pcErrors).Count -gt 0) {
                throw [System.ArgumentException]::new(
                    ("Invalid Preconditions[{0}] on step '{1}': {2}" -f $pcIdx, $StepName, ([string]::Join(' ', @($pcErrors)))),
                    'Workflow'
                )
            }
        }

        $normalized.Preconditions = @()
        foreach ($pc in $pcList) {
            $normalized.Preconditions += Copy-IdleDataObject -Value $pc
        }
    }
    elseif ($hasPreconditionValue) {
        if ($rawPrecondition -isnot [System.Collections.IDictionary]) {
            throw [System.ArgumentException]::new(
                ("Workflow step '{0}': Precondition must be a hashtable (condition node). Use 'Preconditions' for the canonical array form." -f $StepName),
                'Workflow'
            )
        }

        $pcErrors = Test-IdleConditionSchema -Condition ([hashtable]$rawPrecondition) -StepName $StepName
        if (@($pcErrors).Count -gt 0) {
            throw [System.ArgumentException]::new(
                ("Invalid Precondition on step '{0}': {1}" -f $StepName, ([string]::Join(' ', @($pcErrors)))),
                'Workflow'
            )
        }

        $normalized.Preconditions = @(
            Copy-IdleDataObject -Value $rawPrecondition
        )
    }

    if (Test-IdleWorkflowStepKey -Step $Step -Key 'OnPreconditionFalse') {
        $rawOnPreconditionFalseValue = Get-IdlePropertyValue -Object $Step -Name 'OnPreconditionFalse'
        if ($null -ne $rawOnPreconditionFalseValue) {
            $rawOnPreconditionFalse = [string]$rawOnPreconditionFalseValue
            if (-not [string]::IsNullOrWhiteSpace($rawOnPreconditionFalse)) {
                if ($rawOnPreconditionFalse -notin @('Blocked', 'Fail', 'Continue')) {
                    throw [System.ArgumentException]::new(
                        ("Workflow step '{0}': OnPreconditionFalse must be 'Blocked', 'Fail', or 'Continue'. Got: '{1}'." -f $StepName, $rawOnPreconditionFalse),
                        'Workflow'
                    )
                }

                $normalized.OnPreconditionFalse = $rawOnPreconditionFalse
            }
        }
    }

    if (Test-IdleWorkflowStepKey -Step $Step -Key 'PreconditionEvent') {
        $rawPreconditionEvent = Get-IdlePropertyValue -Object $Step -Name 'PreconditionEvent'
        if ($null -ne $rawPreconditionEvent) {
            if ($rawPreconditionEvent -isnot [System.Collections.IDictionary]) {
                throw [System.ArgumentException]::new(
                    ("Workflow step '{0}': PreconditionEvent must be a hashtable." -f $StepName),
                    'Workflow'
                )
            }

            $pcEvtType = if ($rawPreconditionEvent.Contains('Type')) { [string]$rawPreconditionEvent['Type'] } else { $null }
            if ([string]::IsNullOrWhiteSpace($pcEvtType)) {
                throw [System.ArgumentException]::new(
                    ("Workflow step '{0}': PreconditionEvent.Type is required and must be a non-empty string." -f $StepName),
                    'Workflow'
                )
            }

            $pcEvtMsg = if ($rawPreconditionEvent.Contains('Message')) { [string]$rawPreconditionEvent['Message'] } else { $null }
            if ([string]::IsNullOrWhiteSpace($pcEvtMsg)) {
                throw [System.ArgumentException]::new(
                    ("Workflow step '{0}': PreconditionEvent.Message is required and must be a non-empty string." -f $StepName),
                    'Workflow'
                )
            }

            # PreconditionEvent.Data is optional but must be a hashtable if present.
            if ($rawPreconditionEvent.Contains('Data') -and $null -ne $rawPreconditionEvent['Data']) {
                if ($rawPreconditionEvent['Data'] -isnot [System.Collections.IDictionary]) {
                    throw [System.ArgumentException]::new(
                        ("Workflow step '{0}': PreconditionEvent.Data must be a hashtable." -f $StepName),
                        'Workflow'
                    )
                }
            }

            $normalized.PreconditionEvent = Copy-IdleDataObject -Value $rawPreconditionEvent
        }
    }

    return $normalized
}

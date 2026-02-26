Set-StrictMode -Version Latest

function ConvertTo-IdleWorkflowStepPreconditionSettings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Step,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $StepName,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $PlanningContext
    )

    $normalized = @{
        Precondition        = $null
        OnPreconditionFalse = $null
        PreconditionEvent   = $null
    }

    # Runtime Precondition: evaluated at execution time (not planning time).
    # Uses the same declarative condition DSL as Condition.
    if (Test-IdleWorkflowStepKey -Step $Step -Key 'Precondition') {
        $rawPrecondition = Get-IdlePropertyValue -Object $Step -Name 'Precondition'
        if ($null -ne $rawPrecondition) {
            if ($rawPrecondition -isnot [System.Collections.IDictionary]) {
                throw [System.ArgumentException]::new(
                    ("Workflow step '{0}': Precondition must be a hashtable (condition node)." -f $StepName),
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

            $warningSink = $null
            $planObj = $PlanningContext.Plan
            if ($null -ne $planObj) {
                if ($planObj -is [System.Collections.IDictionary]) {
                    if ($planObj.Contains('Warnings')) { $warningSink = $planObj['Warnings'] }
                } else {
                    $wProp = $planObj.PSObject.Properties['Warnings']
                    if ($null -ne $wProp) { $warningSink = $wProp.Value }
                }
            }
            Assert-IdleConditionPathsResolvable -Condition ([hashtable]$rawPrecondition) -Context $PlanningContext -StepName $StepName -Source 'Precondition' -AllowMissingRequestContextPaths -WarningSink $warningSink
            $normalized.Precondition = Copy-IdleDataObject -Value $rawPrecondition
        }
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

function New-IdlePlanObject {
    <#
    .SYNOPSIS
    Builds a deterministic plan from a request and a workflow definition.

    .DESCRIPTION
    Loads and validates the workflow definition (PSD1) and creates a normalized plan object.
    This is a planning-only artifact. Execution is handled by Invoke-IdlePlan later.

    .PARAMETER WorkflowPath
    Path to the workflow definition (PSD1).

    .PARAMETER Request
    Lifecycle request object (must contain LifecycleEvent and CorrelationId).

    .PARAMETER Providers
    Optional provider registry/collection. Not used in this increment; stored for later.

    .OUTPUTS
    PSCustomObject (PSTypeName: IdLE.Plan)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $WorkflowPath,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Request,

        [Parameter()]
        [AllowNull()]
        [object] $Providers
    )

    # Ensure required request properties exist without hard-typing the request class.
    $reqProps = $Request.PSObject.Properties.Name
    if ($reqProps -notcontains 'LifecycleEvent') {
        throw [System.ArgumentException]::new("Request object must contain property 'LifecycleEvent'.", 'Request')
    }
    if ($reqProps -notcontains 'CorrelationId') {
        throw [System.ArgumentException]::new("Request object must contain property 'CorrelationId'.", 'Request')
    }

    # Validate workflow and ensure it matches the request's LifecycleEvent.
    $workflow = Test-IdleWorkflowDefinitionObject -WorkflowPath $WorkflowPath -Request $Request

    # Create the plan object (planning artifact).
    # Steps will be populated after we have a stable plan context for condition evaluation.
    $plan = [pscustomobject]@{
        PSTypeName     = 'IdLE.Plan'
        WorkflowName   = [string]$workflow.Name
        LifecycleEvent = [string]$workflow.LifecycleEvent
        CorrelationId  = [string]$Request.CorrelationId
        Actor          = if ($reqProps -contains 'Actor') { [string]$Request.Actor } else { $null }
        CreatedUtc     = [DateTime]::UtcNow
        Steps          = @()
        Actions        = @()
        Warnings       = @()
        Providers      = $Providers
    }

    # Build a planning context for condition evaluation.
    # This allows conditions to reference "Plan.*" paths (e.g. Plan.LifecycleEvent).
    $planningContext = [pscustomobject]@{
        Plan     = $plan
        Request  = $Request
        Workflow = $workflow
    }

    # Normalize steps into a stable internal representation.
    # We deliberately keep step entries as PSCustomObject to avoid cross-module class loading issues.
    # Step conditions are evaluated during planning and may mark steps as NotApplicable.
    $normalizedSteps = @()
    foreach ($s in @($workflow.Steps)) {

        # Breaking change: "When" is no longer supported. Use "Condition" instead.
        if ($s.ContainsKey('When')) {
            throw [System.ArgumentException]::new(
                "Workflow step '$($s.Name)' uses key 'When'. This has been renamed to 'Condition'. Please update the workflow definition.",
                'Workflow'
            )
        }

        $condition = if ($s.ContainsKey('Condition')) { $s.Condition } else { $null }

        $status = 'Planned'
        if ($null -ne $condition) {
            $schemaErrors = Test-IdleConditionSchema -Condition $condition -StepName ([string]$s.Name)
            if ($schemaErrors.Count -gt 0) {
                throw [System.ArgumentException]::new(
                    ("Invalid Condition on step '{0}': {1}" -f [string]$s.Name, ([string]::Join(' ', @($schemaErrors)))),
                    'Workflow'
                )
            }

            $isApplicable = Test-IdleCondition -Condition $condition -Context $planningContext
            if (-not $isApplicable) {
                $status = 'NotApplicable'
            }
        }

        $normalizedSteps += [pscustomobject]@{
            PSTypeName   = 'IdLE.PlanStep'
            Name         = [string]$s.Name
            Type         = [string]$s.Type
            Description  = if ($s.ContainsKey('Description')) { [string]$s.Description } else { $null }
            Condition    = $condition
            With         = if ($s.ContainsKey('With')) { $s.With } else { $null }   # Parameter bag; validated later.
            Status       = $status
        }
    }

    $plan.Steps = $normalizedSteps

    return $plan
}

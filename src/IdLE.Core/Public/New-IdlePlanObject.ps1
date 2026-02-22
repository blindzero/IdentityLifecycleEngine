function New-IdlePlanObject {
    <#
    .SYNOPSIS
    Builds a deterministic plan from a request and a workflow definition.

    .DESCRIPTION
    Loads and validates the workflow definition (PSD1) and creates a normalized plan object.
    This is a planning-only artifact. Execution is handled by Invoke-IdlePlanObject later.

    Planning responsibilities:
    - Execute ContextResolvers (read-only) to populate Request.Context before condition evaluation.
    - Create a data-only request snapshot for deterministic exports and auditing.
    - Normalize workflow steps to IdLE.PlanStep objects.
    - Evaluate step conditions during planning and mark steps as NotApplicable.
    - Validate required provider capabilities fail-fast (includes OnFailureSteps).

    .PARAMETER WorkflowPath
    Path to the workflow definition (PSD1).

    .PARAMETER Request
    Lifecycle request object (must contain LifecycleEvent and CorrelationId).

    .PARAMETER Providers
    Provider map passed through to the plan for later execution.

    .OUTPUTS
    PSCustomObject (PSTypeName: IdLE.Plan)

    .EXAMPLE
    $plan = New-IdlePlanObject -WorkflowPath ./workflows/joiner.psd1 -Request $request -Providers $providers

    Builds a plan from a workflow definition and lifecycle request with the specified provider registry.
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

    # Reject requests that contain Request.Identity — identity snapshots belong under Request.Context.Identity.
    if ($reqProps -contains 'Identity') {
        throw [System.ArgumentException]::new(
            "Request object must not contain property 'Identity'. Identity-related data belongs under 'Context.Identity' (see Request.Context).",
            'Request'
        )
    }

    # Validate workflow and ensure it matches the request's LifecycleEvent.
    $workflow = Test-IdleWorkflowDefinitionObject -WorkflowPath $WorkflowPath -Request $Request

    # Execute ContextResolvers (planning-time, read-only) before condition evaluation.
    # Resolvers populate Request.Context.* so that conditions can reference resolved data.
    $workflowContextResolvers = Get-IdlePropertyValue -Object $workflow -Name 'ContextResolvers'
    if ($null -ne $workflowContextResolvers -and @($workflowContextResolvers).Count -gt 0) {
        Invoke-IdleContextResolvers -Resolvers @($workflowContextResolvers) -Providers $Providers -Request $Request
    }

    # Create a data-only snapshot AFTER resolvers have run so that resolved context is captured.
    $requestSnapshot = [pscustomobject]@{
        PSTypeName     = 'IdLE.LifecycleRequestSnapshot'
        LifecycleEvent = ConvertTo-NullIfEmptyString -Value ([string]$Request.LifecycleEvent)
        CorrelationId  = ConvertTo-NullIfEmptyString -Value ([string]$Request.CorrelationId)
        Actor          = if ($reqProps -contains 'Actor') { ConvertTo-NullIfEmptyString -Value ([string]$Request.Actor) } else { $null }
        IdentityKeys   = if ($reqProps -contains 'IdentityKeys') { Copy-IdleDataObject -Value $Request.IdentityKeys } else { $null }
        Intent         = if ($reqProps -contains 'Intent') { Copy-IdleDataObject -Value $Request.Intent } else { $null }
        Context        = if ($reqProps -contains 'Context') { Copy-IdleDataObject -Value $Request.Context } else { $null }
    }

    # Create the plan object (planning artifact).
    $plan = [pscustomobject]@{
        PSTypeName     = 'IdLE.Plan'
        WorkflowName   = [string]$workflow.Name
        LifecycleEvent = [string]$workflow.LifecycleEvent
        CorrelationId  = [string]$requestSnapshot.CorrelationId
        Request        = $requestSnapshot
        Actor          = $requestSnapshot.Actor
        CreatedUtc     = [DateTime]::UtcNow

        Steps          = @()
        OnFailureSteps = @()

        Actions        = @()
        Warnings       = @()
        Providers      = $Providers
    }

    # Build a planning context for condition evaluation.
    $planningContext = [pscustomobject]@{
        Plan     = $plan
        Request  = $Request
        Workflow = $workflow
    }

    # Load StepMetadataCatalog (trusted extension point).
    $stepMetadataCatalog = Resolve-IdleStepMetadataCatalog -Providers $Providers

    $workflowOnFailureSteps = Get-IdlePropertyValue -Object $workflow -Name 'OnFailureSteps'

    # Normalize primary and OnFailure steps.
    # IMPORTANT:
    # ConvertTo-IdleWorkflowSteps may return an empty array that would otherwise collapse to $null on assignment.
    $plan.Steps = @(ConvertTo-IdleWorkflowSteps -WorkflowSteps $workflow.Steps -PlanningContext $planningContext -StepMetadataCatalog $stepMetadataCatalog)
    $plan.OnFailureSteps = @(ConvertTo-IdleWorkflowSteps -WorkflowSteps $workflowOnFailureSteps -PlanningContext $planningContext -StepMetadataCatalog $stepMetadataCatalog)

    # Fail-fast capability validation (includes OnFailureSteps).
    $allStepsForCapabilities = @()
    $allStepsForCapabilities += @($plan.Steps)
    $allStepsForCapabilities += @($plan.OnFailureSteps)

    Assert-IdlePlanCapabilitiesSatisfied -Steps $allStepsForCapabilities -Providers $Providers

    return $plan
}

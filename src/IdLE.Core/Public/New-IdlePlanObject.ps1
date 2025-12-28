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

    # Normalize steps into a stable internal representation.
    # We deliberately keep step entries as PSCustomObject to avoid cross-module class loading issues.
    $normalizedSteps = @()
    foreach ($s in @($workflow.Steps)) {
        $normalizedSteps += [pscustomobject]@{
            PSTypeName   = 'IdLE.PlanStep'
            Name         = [string]$s.Name
            Type         = [string]$s.Type
            Description  = if ($s.ContainsKey('Description')) { [string]$s.Description } else { $null }
            When         = if ($s.ContainsKey('When')) { $s.When } else { $null }   # Declarative; evaluated later.
            With         = if ($s.ContainsKey('With')) { $s.With } else { $null }   # Parameter bag; validated later.
        }
    }

    # Create the plan object. Actions are empty in this increment.
    # Warnings are an extensibility point (e.g. missing optional inputs).
    $plan = [pscustomobject]@{
        PSTypeName     = 'IdLE.Plan'
        WorkflowName   = [string]$workflow.Name
        LifecycleEvent = [string]$workflow.LifecycleEvent
        CorrelationId  = [string]$Request.CorrelationId
        Actor          = if ($reqProps -contains 'Actor') { [string]$Request.Actor } else { $null }
        CreatedUtc     = [DateTime]::UtcNow
        Steps          = $normalizedSteps
        Actions        = @()
        Warnings       = @()
        Providers      = $Providers
    }

    return $plan
}

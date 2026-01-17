function Test-IdleWorkflowDefinitionObject {
    <#
    .SYNOPSIS
    Loads and strictly validates a workflow definition (PSD1).

    .DESCRIPTION
    Performs strict schema validation (unknown keys = error), verifies the workflow is data-only
    (no ScriptBlocks), and optionally validates compatibility with a LifecycleRequest.

    .PARAMETER WorkflowPath
    Path to the workflow definition PSD1.

    .PARAMETER Request
    Optional request object. If provided, Workflow.LifecycleEvent must match Request.LifecycleEvent.

    .OUTPUTS
    PSCustomObject (PSTypeName: IdLE.WorkflowDefinition)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $WorkflowPath,

        [Parameter()]
        [AllowNull()]
        [object] $Request
    )

    # 1) Load PSD1 data (no execution).
    $workflow = Import-IdleWorkflowDefinition -WorkflowPath $WorkflowPath

    # 2) Enforce "data-only": no ScriptBlocks anywhere in the workflow object.
    #    This matches the project's config safety rules.
    Assert-IdleNoScriptBlock -InputObject $workflow -Path 'Workflow'

    # 3) Strict schema validation: unknown keys and missing required keys are errors.
    # using a resizable list to collect all violations and have .Add method available later
    $errors = [System.Collections.Generic.List[string]]::new()
    $schemaErrors = Test-IdleWorkflowSchema -Workflow $workflow
    if ($schemaErrors) {
        foreach ($e in @($schemaErrors)) { $null = $errors.Add([string]$e) }
    }

    # 4) Optional compatibility check with request (LifecycleEvent match).
    if ($null -ne $Request) {
        if (-not ($Request.PSObject.Properties.Name -contains 'LifecycleEvent')) {
            $errors.Add("Request object does not contain required property 'LifecycleEvent'.")
        }
        else {
            $reqEvent = [string]$Request.LifecycleEvent
            $wfEvent = [string]$workflow.LifecycleEvent

            if (-not [string]::IsNullOrWhiteSpace($reqEvent) -and
                -not $reqEvent.Equals($wfEvent, [System.StringComparison]::OrdinalIgnoreCase)) {
                $errors.Add("Workflow LifecycleEvent '$wfEvent' does not match request LifecycleEvent '$reqEvent'.")
            }
        }
    }

    # 4b) Validate step definitions (Name/Type/Condition/With + data-only).
    $idx = 0
    foreach ($s in @($workflow.Steps)) {
        $stepErrors = Test-IdleStepDefinition -Step $s -Index $idx
        foreach ($e in @($stepErrors)) {
            $null = $errors.Add([string]$e)
        }
        $idx++
    }

    # 4c) Validate OnFailureSteps definitions (Name/Type/Condition/With + data-only).
    #     These are executed only when a run fails, but they must be valid workflow steps.
    if ($workflow.ContainsKey('OnFailureSteps') -and $null -ne $workflow.OnFailureSteps) {
        $idx = 0
        foreach ($s in @($workflow.OnFailureSteps)) {
            $stepErrors = Test-IdleStepDefinition -Step $s -Index $idx
            foreach ($e in @($stepErrors)) {
                # Re-label errors so operators can clearly distinguish the step collection.
                $normalizedError = ([string]$e) -replace '^Step\[(\d+)\]', 'OnFailureSteps[$1]'
                $null = $errors.Add($normalizedError)
            }
            $idx++
        }
    }

    if ($errors.Count -gt 0) {
        # Fail early with a single terminating exception, including all violations.
        $message = "Workflow validation failed:`n- " + ($errors -join "`n- ")
        throw [System.ArgumentException]::new($message, 'WorkflowPath')
    }

    # 5) Return normalized object (stable contract for planning).
    #    PSCustomObject avoids class/type load-order problems across modules.
    return [pscustomobject]@{
        PSTypeName     = 'IdLE.WorkflowDefinition'
        Name           = [string]$workflow.Name
        LifecycleEvent = [string]$workflow.LifecycleEvent
        Description    = if ($workflow.ContainsKey('Description')) { [string]$workflow.Description } else { $null }
        Steps          = @($workflow.Steps)
        OnFailureSteps  = if ($workflow.ContainsKey('OnFailureSteps') -and $null -ne $workflow.OnFailureSteps) { @($workflow.OnFailureSteps) } else { @() }
    }
}

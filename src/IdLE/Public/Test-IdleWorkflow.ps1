function Test-IdleWorkflow {
    <#
    .SYNOPSIS
    Validates an IdLE workflow definition file.

    .DESCRIPTION
    Loads and strictly validates a workflow definition (PSD1).
    Throws on validation errors.

    .PARAMETER WorkflowPath
    Path to the workflow definition file (PSD1).

    .PARAMETER Request
    Optional lifecycle request for validating compatibility (LifecycleEvent match).

    .EXAMPLE
    Test-IdleWorkflow -WorkflowPath ./workflows/joiner.psd1 -Request $request

    .OUTPUTS
    System.Object
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

    # Delegate validation to IdLE.Core to keep the meta module thin and stable.
    $wf = Test-IdleWorkflowDefinitionObject -WorkflowPath $WorkflowPath -Request $Request

    # Test-* cmdlets typically return a small report object instead of the full definition.
    return [pscustomobject]@{
        IsValid        = $true
        WorkflowName   = $wf.Name
        LifecycleEvent = $wf.LifecycleEvent
        StepCount      = @($wf.Steps).Count
    }
}

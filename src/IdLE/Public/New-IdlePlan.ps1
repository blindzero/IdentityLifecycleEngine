function New-IdlePlan {
    <#
    .SYNOPSIS
    Creates a deterministic plan from a lifecycle request and a workflow definition.

    .DESCRIPTION
    Delegates plan building to IdLE.Core and returns a plan artifact.
    Providers are passed through for later increments.

    .PARAMETER WorkflowPath
    Path to the workflow definition file (PSD1).

    .PARAMETER Request
    The lifecycle request object created by New-IdleLifecycleRequest.

    .PARAMETER Providers
    Provider registry/collection passed through to planning. (Structure to be defined later.)

    .EXAMPLE
    $plan = New-IdlePlan -WorkflowPath ./workflows/joiner.psd1 -Request $request -Providers $providers

    .OUTPUTS
    System.Object
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

    # Keep meta module thin: delegate planning to IdLE.Core.
    return New-IdlePlanObject -WorkflowPath $WorkflowPath -Request $Request -Providers $Providers
}

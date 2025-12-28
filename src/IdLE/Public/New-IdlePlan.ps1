function New-IdlePlan {
    <#
    .SYNOPSIS
    Creates a deterministic plan from a lifecycle request and a workflow definition.

    .DESCRIPTION
    Loads and validates a workflow definition (PSD1) and builds a deterministic plan for execution.
    This is a stub in the core skeleton increment and will be implemented in subsequent commits.

    .PARAMETER Request
    The lifecycle request object created by New-IdleLifecycleRequest.

    .PARAMETER WorkflowPath
    Path to the workflow definition file (PSD1).

    .EXAMPLE
    $req = New-IdleLifecycleRequest -LifecycleEvent Joiner -Actor 'alice@contoso.com' -CorrelationId (New-Guid)
    New-IdlePlan -Request $req -WorkflowPath ./workflows/joiner.psd1

    .OUTPUTS
    System.Object
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Request,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $WorkflowPath
    )

    throw 'Not implemented: New-IdlePlan will be implemented in IdLE.Core in a subsequent increment.'
}

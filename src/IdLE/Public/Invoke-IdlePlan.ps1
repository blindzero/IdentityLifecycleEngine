function Invoke-IdlePlan {
    <#
    .SYNOPSIS
    Executes an IdLE plan.

    .DESCRIPTION
    Executes a previously created plan in a deterministic way and emits structured events.
    Providers are passed through to execution (structure will be defined later).

    .PARAMETER Plan
    The plan object created by New-IdlePlan.

    .PARAMETER Providers
    Provider registry/collection passed through to execution. (Structure to be defined later.)

    .EXAMPLE
    Invoke-IdlePlan -Plan $plan -Providers $providers

    .OUTPUTS
    System.Object
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Plan,

        [Parameter()]
        [AllowNull()]
        [object] $Providers
    )

    if ($PSCmdlet.ShouldProcess('IdLE Plan', 'Invoke')) {
        throw 'Not implemented: Invoke-IdlePlan will be implemented in IdLE.Core in a subsequent increment.'
    }
}

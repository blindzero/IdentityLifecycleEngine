Set-StrictMode -Version Latest

function Get-IdleReadOnlyCapabilities {
    <#
    .SYNOPSIS
    Returns the allow-list of read-only capabilities usable in ContextResolvers.

    .DESCRIPTION
    ContextResolvers may only invoke capabilities from this allow-list.
    This enforces the read-only guarantee at planning time: resolvers cannot
    trigger mutations or side effects via the planning pipeline.

    Only capabilities that are safe to invoke at planning time (no side effects,
    deterministic, serializable output) should be added to this list.

    .OUTPUTS
    String[]

    .EXAMPLE
    $allowed = Get-IdleReadOnlyCapabilities
    # Returns: @('IdLE.Entitlement.List')
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param()

    return @(
        'IdLE.Entitlement.List'
    )
}

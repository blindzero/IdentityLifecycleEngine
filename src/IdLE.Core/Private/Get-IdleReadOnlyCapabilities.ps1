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

    Each capability in this list has a predefined output path in Request.Context
    (see Get-IdleCapabilityContextPath).

    .OUTPUTS
    String[]

    .EXAMPLE
    $allowed = Get-IdleReadOnlyCapabilities
    # Returns: @('IdLE.Entitlement.List', 'IdLE.Identity.Read')
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param()

    return @(
        'IdLE.Entitlement.List'
        'IdLE.Identity.Read'
    )
}

function Get-IdleCapabilityContextPath {
    <#
    .SYNOPSIS
    Returns the predefined Request.Context sub-path for a read-only capability.

    .DESCRIPTION
    Each read-only capability allowed in ContextResolvers writes its result to a fixed,
    predefined path under Request.Context. This prevents user-configurable overwrites
    and ensures consistent context shape across workflows.

    The path is relative to Request.Context (e.g., 'Identity.Entitlements' maps to
    Request.Context.Identity.Entitlements).

    .PARAMETER Capability
    The capability identifier (must be in the read-only allow-list).

    .OUTPUTS
    String

    .EXAMPLE
    Get-IdleCapabilityContextPath -Capability 'IdLE.Entitlement.List'
    # Returns: 'Identity.Entitlements'

    .EXAMPLE
    Get-IdleCapabilityContextPath -Capability 'IdLE.Identity.Read'
    # Returns: 'Identity.Profile'
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Capability
    )

    switch ($Capability) {
        'IdLE.Entitlement.List' { return 'Identity.Entitlements' }
        'IdLE.Identity.Read'    { return 'Identity.Profile' }
        default {
            throw [System.ArgumentException]::new(
                "No predefined context path defined for capability '$Capability'.",
                'Capability'
            )
        }
    }
}

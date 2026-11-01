Set-StrictMode -Version Latest

function Get-IdleADEntitlementKind {
    <#
    .SYNOPSIS
    Returns the canonical entitlement Kind supported by the AD provider.

    .DESCRIPTION
    The AD provider only manages group memberships. Any other Kind is rejected so that,
    for example, an 'AdministrativeUnit' entitlement is never resolved as a group of the same name.

    .PARAMETER Kind
    The entitlement Kind to validate (case-insensitive).

    .OUTPUTS
    System.String
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Kind
    )

    if ([string]::Equals($Kind, 'Group', [System.StringComparison]::OrdinalIgnoreCase)) {
        return 'Group'
    }

    throw "Entitlement Kind '$Kind' is not supported by the AD provider. Supported Kinds: Group."
}

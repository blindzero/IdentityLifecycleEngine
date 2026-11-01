Set-StrictMode -Version Latest

function Get-IdleEntraIDEntitlementKind {
    <#
    .SYNOPSIS
    Returns the canonical entitlement Kind supported by the Entra ID provider.

    .DESCRIPTION
    The Entra ID provider manages group and administrative unit memberships. Any other Kind
    (including misspellings such as 'Groups') is rejected so that it cannot silently match nothing.

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

    foreach ($supportedKind in @('Group', 'AdministrativeUnit')) {
        if ([string]::Equals($Kind, $supportedKind, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $supportedKind
        }
    }

    throw "Entitlement Kind '$Kind' is not supported by the Entra ID provider. Supported Kinds: Group, AdministrativeUnit."
}

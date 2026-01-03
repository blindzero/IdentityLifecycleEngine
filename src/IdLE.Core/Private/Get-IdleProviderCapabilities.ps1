Set-StrictMode -Version Latest

function Get-IdleProviderCapabilities {
    <#
    .SYNOPSIS
    Returns the advertised capabilities of a provider instance.

    .DESCRIPTION
    Capabilities are stable string identifiers that describe what a provider can do.
    Steps will declare required capabilities, and the core will validate that the
    required capabilities are available before executing a plan.

    Providers can advertise capabilities explicitly by implementing a ScriptMethod
    named 'GetCapabilities' that returns a list of capability strings.

    For backward compatibility (during the migration), this function can infer a
    minimal set of capabilities from well-known provider methods when no explicit
    advertisement exists.

    .PARAMETER Provider
    The provider instance to read capabilities from.

    .PARAMETER AllowInference
    When set, capabilities may be inferred from provider methods if the provider
    does not explicitly advertise capabilities via GetCapabilities().

    .OUTPUTS
    System.String[]
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Provider,

        [Parameter()]
        [switch] $AllowInference
    )

    $capabilities = @()

    # Prefer explicit advertisement (provider-controlled, deterministic).
    $hasGetCapabilitiesMethod = $Provider.PSObject.Methods.Name -contains 'GetCapabilities'
    if ($hasGetCapabilitiesMethod) {
        $capabilities = @(& $Provider.GetCapabilities())
    }
    elseif ($AllowInference) {
        # Migration helper: infer a minimal set from known method names.
        # We keep this conservative to avoid accidentally overstating capabilities.
        $methodNames = @($Provider.PSObject.Methods.Name)

        if ($methodNames -contains 'GetIdentity') {
            $capabilities += 'Identity.Read'
        }
        if ($methodNames -contains 'EnsureAttribute') {
            $capabilities += 'Identity.Attribute.Ensure'
        }
        if ($methodNames -contains 'DisableIdentity') {
            $capabilities += 'Identity.Disable'
        }
    }

    # Normalize, validate, and return a stable list.
    $normalized = @()
    foreach ($c in @($capabilities)) {
        if ($null -eq $c) {
            continue
        }

        $s = ($c -as [string]).Trim()
        if ([string]::IsNullOrWhiteSpace($s)) {
            continue
        }

        # Capability naming convention:
        # - dot-separated segments
        # - no whitespace
        # - starts with a letter
        # Example: 'Entitlement.Write', 'Identity.Attribute.Ensure'
        if ($s -notmatch '^[A-Za-z][A-Za-z0-9]*(\.[A-Za-z0-9]+)+$') {
            throw "Provider capability '$s' is invalid. Expected dot-separated segments like 'Identity.Read' or 'Entitlement.Write'."
        }

        $normalized += $s
    }

    return @($normalized | Sort-Object -Unique)
}

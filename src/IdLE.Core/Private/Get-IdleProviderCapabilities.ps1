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
    $capabilitySource = 'none'

    # Prefer explicit advertisement (provider-controlled, deterministic).
    $hasGetCapabilitiesMethod = $Provider.PSObject.Methods.Name -contains 'GetCapabilities'
    if ($hasGetCapabilitiesMethod) {
        $capabilities = @($Provider.GetCapabilities())
        $capabilitySource = 'explicit'
    }
    elseif ($AllowInference) {
        # Migration helper: infer a minimal set from known method names.
        # We keep this conservative to avoid accidentally overstating capabilities.
        $methodNames = @($Provider.PSObject.Methods.Name)

        if ($methodNames -contains 'GrantEntitlement') {
            $capabilities += 'IdLE.Entitlement.Grant'
        }
        if ($methodNames -contains 'ListEntitlements') {
            $capabilities += 'IdLE.Entitlement.List'
        }
        if ($methodNames -contains 'RevokeEntitlement') {
            $capabilities += 'IdLE.Entitlement.Revoke'
        }
        if ($methodNames -contains 'EnsureAttribute') {
            $capabilities += 'IdLE.Identity.Attribute.Ensure'
        }
        if ($methodNames -contains 'DisableIdentity') {
            $capabilities += 'IdLE.Identity.Disable'
        }
        if ($methodNames -contains 'GetIdentity') {
            $capabilities += 'IdLE.Identity.Read'
        }

        $capabilitySource = 'inferred'
    }

    # Normalize, validate, and return a stable list.
    $normalized = New-Object System.Collections.Generic.List[string]
    $seen = New-Object System.Collections.Generic.HashSet[string]
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

        # Normalize legacy capability names to canonical form
        # Note: EventSink is not available here during provider capability discovery
        # Warnings will be emitted during plan-time validation instead
        $canonical = ConvertTo-IdleCanonicalCapability -Capability $s -EventSink $null

        if ($seen.Add($canonical)) {
            $null = $normalized.Add($canonical)
        }
    }

    if ($capabilitySource -eq 'explicit') {
        return @($normalized | Sort-Object -Unique)
    }

    # Preserve inference ordering to keep well-known capabilities in priority order
    # (e.g., entitlement operations before identity operations).
    return @($normalized)
}

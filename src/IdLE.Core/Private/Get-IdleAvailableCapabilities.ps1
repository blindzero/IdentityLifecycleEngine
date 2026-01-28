Set-StrictMode -Version Latest

function Get-IdleAvailableCapabilities {
    <#
    .SYNOPSIS
    Aggregates capabilities from all providers.

    .DESCRIPTION
    Collects capabilities from all provider instances and returns a unique sorted list.
    Uses the simpler nested helper version of Get-IdleProviderCapabilities that directly
    calls GetCapabilities() without inference logic.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object] $Providers
    )

    function Get-ProviderCapabilitiesSimple {
        <#
        .SYNOPSIS
        Gets the capability list advertised by a provider (simplified version).

        .DESCRIPTION
        Providers are expected to expose a GetCapabilities() method.
        If not present, the provider is treated as advertising no capabilities.
        This is the planning-time version without inference logic.
        #>
        [CmdletBinding()]
        param(
            [Parameter()]
            [AllowNull()]
            [object] $Provider
        )

        if ($null -eq $Provider) {
            return @()
        }

        if ($Provider.PSObject.Methods.Name -contains 'GetCapabilities') {
            $caps = $Provider.GetCapabilities()
            if ($null -eq $caps) {
                return @()
            }
            return @(
                $caps |
                Where-Object { $null -ne $_ } |
                ForEach-Object {
                    $rawCap = ([string]$_).Trim()
                    if (-not [string]::IsNullOrWhiteSpace($rawCap)) {
                        ConvertTo-IdleNormalizedCapability -Capability $rawCap
                    }
                } |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                Sort-Object -Unique
            )
        }

        return @()
    }

    $providerInstances = @(Get-IdleProvidersFromMap -Providers $Providers)

    $caps = @()
    foreach ($p in $providerInstances) {
        $caps += @(Get-ProviderCapabilitiesSimple -Provider $p)
    }

    return @($caps | Sort-Object -Unique)
}

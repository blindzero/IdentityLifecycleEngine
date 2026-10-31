function Get-IdleProviderSources {
    <#
    .SYNOPSIS
    Returns the provenance of every provider in the Providers map (alias -> source record).

    .DESCRIPTION
    Providers are map entries that expose GetCapabilities(). Other entries (StepRegistry, StepMetadata,
    AuthSessionBroker, placeholders) are not providers and are skipped.

    The module of a provider is the module that defines its GetCapabilities script method. Provider
    objects created outside a module (e.g. in a host script) have no module.

    .PARAMETER Providers
    The Providers map passed to planning or execution.

    .OUTPUTS
    Ordered hashtable mapping provider alias (sorted) to a source record (see ConvertTo-IdleSourceInfo).
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object] $Providers
    )

    $sources = [ordered]@{}

    if ($null -eq $Providers) {
        return $sources
    }

    $entries = @{}
    if ($Providers -is [System.Collections.IDictionary]) {
        foreach ($key in $Providers.Keys) {
            $entries[[string]$key] = $Providers[$key]
        }
    }
    else {
        foreach ($prop in $Providers.PSObject.Properties) {
            $entries[$prop.Name] = $prop.Value
        }
    }

    foreach ($alias in @($entries.Keys | Sort-Object)) {
        $provider = $entries[$alias]
        if ($null -eq $provider) {
            continue
        }

        $method = $provider.PSObject.Methods['GetCapabilities']
        if ($null -eq $method) {
            continue
        }

        $module = if ($method -is [System.Management.Automation.PSScriptMethod]) { $method.Script.Module } else { $null }
        $sources[$alias] = ConvertTo-IdleSourceInfo -Module $module
    }

    return $sources
}

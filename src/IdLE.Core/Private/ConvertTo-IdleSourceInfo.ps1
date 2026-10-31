function ConvertTo-IdleSourceInfo {
    <#
    .SYNOPSIS
    Creates the data-only provenance record for a step handler or provider.

    .DESCRIPTION
    Returns @{ Module; Version } for the given module. If the module is unknown (e.g. a host-defined
    function or provider object without a module), Module and Version are $null.

    .PARAMETER Module
    The module that defines the handler or provider, or $null if unknown.

    .OUTPUTS
    Ordered hashtable with keys Module, Version.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [System.Management.Automation.PSModuleInfo] $Module
    )

    if ($null -eq $Module) {
        return [ordered]@{
            Module  = $null
            Version = $null
        }
    }

    return [ordered]@{
        Module  = $Module.Name
        Version = $Module.Version.ToString()
    }
}

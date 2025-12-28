function Get-IdleStepRegistry {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object] $Providers
    )

    # Registry maps workflow Step.Type -> handler.
    # Handler can be:
    # - string      : PowerShell function name
    # - scriptblock : executable handler (ideal for tests / hosts)
    $registry = [hashtable]::new([System.StringComparer]::OrdinalIgnoreCase)

    if ($null -eq $Providers) {
        return $registry
    }

    # 1) Providers as hashtable / dictionary (most common in tests)
    if ($Providers -is [hashtable] -or $Providers -is [System.Collections.IDictionary]) {
        if ($Providers.Contains('StepRegistry') -and $Providers['StepRegistry'] -is [hashtable]) {
            # Clone to avoid mutating host-provided hashtable during execution.
            $source = $Providers['StepRegistry']
            foreach ($k in $source.Keys) {
                $registry[[string]$k] = $source[$k]
            }
        }

        return $registry
    }

    # 2) Providers as object with property StepRegistry (host objects)
    # StrictMode-safe: do NOT access $Providers.StepRegistry unless the property exists.
    $prop = $Providers.PSObject.Properties['StepRegistry']
    if ($null -ne $prop -and $prop.Value -is [hashtable]) {
        $source = $prop.Value
        foreach ($k in $source.Keys) {
            $registry[[string]$k] = $source[$k]
        }
    }

    return $registry
}

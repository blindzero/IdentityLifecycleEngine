function Get-IdleStepRegistry {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object] $Providers
    )

    # Registry maps workflow Step.Type -> handler function name (string).
    #
    # Trust boundary:
    # - The registry is a host-provided extension point. It is not loaded from workflow configuration.
    # - Workflows are data-only and must not contain executable code.
    #
    # Security / secure defaults:
    # - Only string handlers (function names) are supported.
    # - ScriptBlock handlers are intentionally rejected to avoid arbitrary code execution.

    $registry = [hashtable]::new([System.StringComparer]::OrdinalIgnoreCase)

    # 1) Copy host-provided StepRegistry (optional)
    # We support two shapes for compatibility:
    # - Providers.StepRegistry (hashtable)
    # - Providers['StepRegistry'] (hashtable)
    $hostRegistry = $null

    if ($null -ne $Providers) {
        if ($Providers -is [hashtable] -and $Providers.ContainsKey('StepRegistry')) {
            $hostRegistry = $Providers['StepRegistry']
        }
        elseif ($Providers.PSObject.Properties.Name -contains 'StepRegistry') {
            $hostRegistry = $Providers.StepRegistry
        }
    }

    if ($null -ne $hostRegistry) {
        if ($hostRegistry -isnot [hashtable]) {
            throw [System.ArgumentException]::new('Providers.StepRegistry must be a hashtable that maps Step.Type to a function name (string).', 'Providers')
        }

        foreach ($key in $hostRegistry.Keys) {
            if ($null -eq $key -or [string]::IsNullOrWhiteSpace([string]$key)) {
                throw [System.ArgumentException]::new('Providers.StepRegistry contains an empty step type key.', 'Providers')
            }

            $value = $hostRegistry[$key]

            if ($value -is [scriptblock]) {
                throw [System.ArgumentException]::new(
                    "Providers.StepRegistry entry for step type '$key' is a ScriptBlock. ScriptBlock handlers are not allowed. Provide a function name (string) instead.",
                    'Providers'
                )
            }

            if ($value -isnot [string] -or [string]::IsNullOrWhiteSpace([string]$value)) {
                throw [System.ArgumentException]::new(
                    "Providers.StepRegistry entry for step type '$key' must be a non-empty string (function name).",
                    'Providers'
                )
            }

            $registry[[string]$key] = ([string]$value).Trim()
        }
    }

    # 2) Register built-in steps if available.
    #
    # These are optional modules (Steps.Common, etc.). If they are not loaded, the registry entry is not added.
    if (-not $registry.ContainsKey('IdLE.Step.EmitEvent')) {
        $cmd = Get-Command -Name 'Invoke-IdleStepEmitEvent' -ErrorAction SilentlyContinue
        if ($null -ne $cmd) {
            $registry['IdLE.Step.EmitEvent'] = $cmd.Name
        }
    }

    if (-not $registry.ContainsKey('IdLE.Step.EnsureAttribute')) {
        $cmd = Get-Command -Name 'Invoke-IdleStepEnsureAttribute' -ErrorAction SilentlyContinue
        if ($null -ne $cmd) {
            $registry['IdLE.Step.EnsureAttribute'] = $cmd.Name
        }
    }

    return $registry
}

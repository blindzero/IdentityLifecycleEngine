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

    # Helper: Resolve a step handler name without requiring global command exports.
    #
    # Resolution order:
    # 1) Global command discovery (host imported a module globally) -> "Invoke-IdleStepX"
    # 2) Module-scoped discovery (nested/hidden module loaded) -> "ModuleName\Invoke-IdleStepX"
    function Resolve-IdleStepHandlerName {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $CommandName,

            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $ModuleName
        )

        # 1) Global discovery (optional; supports hosts that import step packs globally)
        $cmd = Get-Command -Name $CommandName -ErrorAction SilentlyContinue
        if ($null -ne $cmd) {
            return $cmd.Name
        }

        # 2) Module-scoped discovery (supports nested modules that are not globally exported)
        $module = Get-Module -Name $ModuleName -All | Select-Object -First 1
        if ($null -eq $module) {
            return $null
        }

        if ($null -ne $module.ExportedCommands -and $module.ExportedCommands.ContainsKey($CommandName)) {

            # Use a module-qualified command name so the engine can invoke it without relying on
            # global session exports. This keeps built-in steps available "within IdLE" only.
            return "$($module.Name)\$CommandName"
        }

        return $null
    }

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
    # Built-in steps are first-party step packs (e.g. IdLE.Steps.Common). They may be loaded as nested
    # modules by the IdLE meta module. In that case, the step commands are not necessarily exported
    # globally. We therefore support module-qualified handler names.
    if (-not $registry.ContainsKey('IdLE.Step.EmitEvent')) {
        $handler = Resolve-IdleStepHandlerName -CommandName 'Invoke-IdleStepEmitEvent' -ModuleName 'IdLE.Steps.Common'
        if (-not [string]::IsNullOrWhiteSpace($handler)) {
            $registry['IdLE.Step.EmitEvent'] = $handler
        }
    }

    if (-not $registry.ContainsKey('IdLE.Step.EnsureAttribute')) {
        $handler = Resolve-IdleStepHandlerName -CommandName 'Invoke-IdleStepEnsureAttribute' -ModuleName 'IdLE.Steps.Common'
        if (-not [string]::IsNullOrWhiteSpace($handler)) {
            $registry['IdLE.Step.EnsureAttribute'] = $handler
        }
    }

    if (-not $registry.ContainsKey('IdLE.Step.EnsureEntitlement')) {
        $handler = Resolve-IdleStepHandlerName -CommandName 'Invoke-IdleStepEnsureEntitlement' -ModuleName 'IdLE.Steps.Common'
        if (-not [string]::IsNullOrWhiteSpace($handler)) {
            $registry['IdLE.Step.EnsureEntitlement'] = $handler
        }
    }

    return $registry
}

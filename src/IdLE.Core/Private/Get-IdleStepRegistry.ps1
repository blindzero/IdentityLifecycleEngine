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

    # 1) Register handlers declared by loaded step packs (StepMetadataCatalog 'Handler' key).
    #
    # First-party and third-party step packs declare their handlers the same way. Handler names are
    # module-qualified, so step packs loaded as nested modules (e.g. by the IdLE meta module) work without
    # exporting their commands globally.
    $stepPackCatalog = Resolve-IdleStepMetadataCatalog -Providers $null

    foreach ($stepType in $stepPackCatalog.Keys) {
        $metadata = $stepPackCatalog[$stepType]
        if ($metadata.ContainsKey('Handler')) {
            $registry[$stepType] = $metadata['Handler']
        }
    }

    # 2) Add host-provided StepRegistry entries (optional) for host-defined step types.
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

            # Host step types are extensions ('<Owner>.IdLE.Step.*') and only supplement step packs:
            # replacing the handler of a step pack step type would run other code than the plan declares.
            $namespaceError = Get-IdleIdentifierNamespaceError -Kind 'StepType' -Identifier ([string]$key)
            if ($null -ne $namespaceError) {
                throw [System.ArgumentException]::new("$namespaceError Registered in Providers.StepRegistry.", 'Providers')
            }

            if ($stepPackCatalog.ContainsKey([string]$key)) {
                throw [System.InvalidOperationException]::new(
                    "DuplicateStepHandler: Step type '$key' is defined by a step pack. Providers.StepRegistry can only register handlers for host-defined step types, not replace step pack handlers."
                )
            }

            $registry[[string]$key] = ([string]$value).Trim()
        }
    }

    return $registry
}

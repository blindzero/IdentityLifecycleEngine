function Resolve-IdleStepMetadataCatalog {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object] $Providers
    )

    # Metadata catalog maps Step.Type -> metadata hashtable.
    #
    # Trust boundary:
    # - The metadata catalog is a host-provided extension point, similar to StepRegistry.
    # - It is not loaded from workflow configuration.
    # - Workflows are data-only and must not contain executable code.
    #
    # Security / secure defaults:
    # - Only data-only metadata (hashtables with scalar/array values) are supported.
    # - ScriptBlock values are intentionally rejected to avoid arbitrary code execution.

    $catalog = [hashtable]::new([System.StringComparer]::OrdinalIgnoreCase)

    # Helper: Resolve a function from a module without requiring global command exports.
    function Resolve-IdleModuleFunction {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $FunctionName,

            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $ModuleName
        )

        # 1) Global discovery (optional; supports hosts that import modules globally)
        $cmd = Get-Command -Name $FunctionName -ErrorAction SilentlyContinue
        if ($null -ne $cmd) {
            return $cmd
        }

        # 2) Module-scoped discovery (supports nested modules that are not globally exported)
        $module = Get-Module -Name $ModuleName -All | Select-Object -First 1
        if ($null -eq $module) {
            return $null
        }

        if ($null -ne $module.ExportedCommands -and $module.ExportedCommands.ContainsKey($FunctionName)) {
            return $module.ExportedCommands[$FunctionName]
        }

        return $null
    }

    # Helper: Validate and merge metadata from a hashtable source.
    function Merge-IdleStepMetadata {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [hashtable] $Target,

            [Parameter(Mandatory)]
            [hashtable] $Source,

            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $SourceName
        )

        foreach ($key in $Source.Keys) {
            if ($null -eq $key -or [string]::IsNullOrWhiteSpace([string]$key)) {
                throw [System.ArgumentException]::new("$SourceName contains an empty step type key.", 'Providers')
            }

            $value = $Source[$key]

            if ($value -isnot [hashtable]) {
                throw [System.ArgumentException]::new(
                    "$SourceName entry for step type '$key' must be a hashtable (metadata object).",
                    'Providers'
                )
            }

            # Validate metadata shape (data-only, no ScriptBlocks).
            foreach ($metaKey in $value.Keys) {
                $metaValue = $value[$metaKey]

                if ($metaValue -is [scriptblock]) {
                    throw [System.ArgumentException]::new(
                        "$SourceName entry for step type '$key' contains a ScriptBlock in metadata key '$metaKey'. ScriptBlocks are not allowed (data-only boundary).",
                        'Providers'
                    )
                }

                # Validate RequiredCapabilities if present.
                if ($metaKey -eq 'RequiredCapabilities') {
                    if ($null -ne $metaValue) {
                        if ($metaValue -is [string]) {
                            # Single capability - validate format.
                            $cap = ([string]$metaValue).Trim()
                            if (-not [string]::IsNullOrWhiteSpace($cap) -and $cap -notmatch '^[A-Za-z][A-Za-z0-9]*(\.[A-Za-z0-9]+)+$') {
                                throw [System.ArgumentException]::new(
                                    "$SourceName entry for step type '$key' declares invalid capability '$cap'. Expected dot-separated segments like 'IdLE.Identity.Read'.",
                                    'Providers'
                                )
                            }
                        }
                        elseif ($metaValue -is [System.Collections.IEnumerable] -and $metaValue -isnot [string]) {
                            # Array of capabilities - validate each.
                            foreach ($c in $metaValue) {
                                if ($null -ne $c) {
                                    $cap = ([string]$c).Trim()
                                    if (-not [string]::IsNullOrWhiteSpace($cap) -and $cap -notmatch '^[A-Za-z][A-Za-z0-9]*(\.[A-Za-z0-9]+)+$') {
                                        throw [System.ArgumentException]::new(
                                            "$SourceName entry for step type '$key' declares invalid capability '$cap'. Expected dot-separated segments like 'IdLE.Identity.Read'.",
                                            'Providers'
                                        )
                                    }
                                }
                            }
                        }
                        else {
                            throw [System.ArgumentException]::new(
                                "$SourceName entry for step type '$key' has invalid RequiredCapabilities value. Expected string or string array.",
                                'Providers'
                            )
                        }
                    }
                }
            }

            # Merge (host metadata overrides built-in).
            $Target[[string]$key] = $value
        }
    }

    # 1) Register built-in step metadata if available.
    #
    # Built-in step metadata comes from first-party step packs (e.g. IdLE.Steps.Common).
    # They may be loaded as nested modules by the IdLE meta module.
    $builtInFunction = Resolve-IdleModuleFunction -FunctionName 'Get-IdleStepMetadataCatalog' -ModuleName 'IdLE.Steps.Common'
    if ($null -ne $builtInFunction) {
        # Ensure we're calling the function from IdLE.Steps.Common, not recursing into ourselves.
        # Check both ModuleName and Source properties as they may vary.
        $functionModule = $builtInFunction.ModuleName
        if ($null -eq $functionModule) {
            $functionModule = $builtInFunction.Source
        }
        
        if ($functionModule -eq 'IdLE.Steps.Common') {
            $builtInMetadata = & $builtInFunction
            if ($null -ne $builtInMetadata -and $builtInMetadata -is [hashtable]) {
                Merge-IdleStepMetadata -Target $catalog -Source $builtInMetadata -SourceName 'Built-in StepMetadata'
            }
        }
    }

    # 2) Copy host-provided StepMetadata (optional) - this overrides built-in.
    # We support two shapes for compatibility:
    # - Providers.StepMetadata (hashtable)
    # - Providers['StepMetadata'] (hashtable)
    $hostMetadata = $null

    if ($null -ne $Providers) {
        if ($Providers -is [hashtable] -and $Providers.ContainsKey('StepMetadata')) {
            $hostMetadata = $Providers['StepMetadata']
        }
        elseif ($Providers.PSObject.Properties.Name -contains 'StepMetadata') {
            $hostMetadata = $Providers.StepMetadata
        }
    }

    if ($null -ne $hostMetadata) {
        if ($hostMetadata -isnot [hashtable]) {
            throw [System.ArgumentException]::new('Providers.StepMetadata must be a hashtable that maps Step.Type to a metadata object (hashtable).', 'Providers')
        }

        Merge-IdleStepMetadata -Target $catalog -Source $hostMetadata -SourceName 'Providers.StepMetadata'
    }

    return $catalog
}

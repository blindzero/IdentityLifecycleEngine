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

    # Helper: Validate WithSchema structure.
    # Every step type must declare WithSchema with RequiredKeys and OptionalKeys string arrays.
    # A key name of '*' in OptionalKeys is allowed as a permissive wildcard for test/internal use.
    function Test-IdleWithSchema {
        [CmdletBinding()]
        param(
            [Parameter()]
            [AllowNull()]
            [object] $Value,

            [Parameter(Mandatory)]
            [string] $StepType,

            [Parameter(Mandatory)]
            [string] $SourceName
        )

        if ($null -eq $Value -or $Value -isnot [hashtable]) {
            throw [System.ArgumentException]::new(
                "$SourceName entry for step type '$StepType' is missing 'WithSchema'. Every step type must declare its With key contract as WithSchema = @{ RequiredKeys = @(...); OptionalKeys = @(...) }.",
                'Providers'
            )
        }

        foreach ($schemaKey in @('RequiredKeys', 'OptionalKeys')) {
            if (-not $Value.ContainsKey($schemaKey)) {
                throw [System.ArgumentException]::new(
                    "$SourceName entry for step type '$StepType' WithSchema is missing '$schemaKey'. Expected a string array (may be empty: @()).",
                    'Providers'
                )
            }

            $keyList = $Value[$schemaKey]
            if ($null -eq $keyList) {
                throw [System.ArgumentException]::new(
                    "$SourceName entry for step type '$StepType' WithSchema.$schemaKey must be a string array (got null).",
                    'Providers'
                )
            }

            # Scalar string is valid as a single-element array
            if ($keyList -is [string]) {
                if ([string]::IsNullOrWhiteSpace($keyList)) {
                    throw [System.ArgumentException]::new(
                        "$SourceName entry for step type '$StepType' WithSchema.$schemaKey contains an empty or whitespace-only key name.",
                        'Providers'
                    )
                }
                continue
            }

            if ($keyList -is [System.Collections.IDictionary]) {
                throw [System.ArgumentException]::new(
                    "$SourceName entry for step type '$StepType' WithSchema.$schemaKey must be a string array, not a hashtable.",
                    'Providers'
                )
            }

            if ($keyList -is [System.Collections.IEnumerable]) {
                foreach ($k in $keyList) {
                    if ($null -eq $k -or $k -isnot [string] -or [string]::IsNullOrWhiteSpace([string]$k)) {
                        throw [System.ArgumentException]::new(
                            "$SourceName entry for step type '$StepType' WithSchema.$schemaKey contains a null, non-string, or empty key name.",
                            'Providers'
                        )
                    }
                }
                continue
            }

            # If it's not IEnumerable and not a string, it's invalid
            if ($keyList -isnot [System.Collections.IEnumerable]) {
                throw [System.ArgumentException]::new(
                    "$SourceName entry for step type '$StepType' WithSchema.$schemaKey must be a string array.",
                    'Providers'
                )
            }
        }

        # Check for duplicates across RequiredKeys and OptionalKeys (case-insensitive)
        $requiredSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $reqKeys = $Value['RequiredKeys']
        if ($reqKeys -is [string]) { $null = $requiredSet.Add($reqKeys) }
        elseif ($reqKeys -is [System.Collections.IEnumerable]) {
            foreach ($k in $reqKeys) { if ($null -ne $k) { $null = $requiredSet.Add([string]$k) } }
        }

        $optKeys = $Value['OptionalKeys']
        if ($optKeys -is [string]) {
            if ($requiredSet.Contains($optKeys)) {
                throw [System.ArgumentException]::new(
                    "$SourceName entry for step type '$StepType' WithSchema has key '$optKeys' in both RequiredKeys and OptionalKeys. Keys must be unique across both sets.",
                    'Providers'
                )
            }
        }
        elseif ($optKeys -is [System.Collections.IEnumerable]) {
            foreach ($k in $optKeys) {
                if ($null -ne $k -and $requiredSet.Contains([string]$k)) {
                    throw [System.ArgumentException]::new(
                        "$SourceName entry for step type '$StepType' WithSchema has key '$k' in both RequiredKeys and OptionalKeys. Keys must be unique across both sets.",
                        'Providers'
                    )
                }
            }
        }
    }

    # Helper: Validate RequiredCapabilities value.
    function Test-IdleRequiredCapabilities {
        [CmdletBinding()]
        param(
            [Parameter()]
            [AllowNull()]
            [object] $Value,

            [Parameter(Mandatory)]
            [string] $StepType,

            [Parameter(Mandatory)]
            [string] $SourceName
        )

        if ($null -eq $Value) {
            return
        }

        if ($Value -is [string]) {
            $cap = ConvertTo-IdleCapabilityIdentifier -Value $Value
            if ($null -ne $cap -and -not (Test-IdleCapabilityIdentifier -Capability $cap)) {
                throw [System.ArgumentException]::new(
                    "$SourceName entry for step type '$StepType' declares invalid capability '$cap'. Expected dot-separated segments like 'IdLE.Identity.Read'.",
                    'Providers'
                )
            }
            return
        }

        # Explicitly reject dictionary/hashtable values; they are not valid capability lists.
        if ($Value -is [System.Collections.IDictionary] -or $Value -is [hashtable]) {
            throw [System.ArgumentException]::new(
                "$SourceName entry for step type '$StepType' has invalid RequiredCapabilities value. Expected string or string array.",
                'Providers'
            )
        }

        if ($Value -is [System.Collections.IEnumerable]) {
            foreach ($c in $Value) {
                if ($null -eq $c) {
                    continue
                }

                if ($c -isnot [string]) {
                    throw [System.ArgumentException]::new(
                        "$SourceName entry for step type '$StepType' has invalid RequiredCapabilities value. Expected string or string array.",
                        'Providers'
                    )
                }

                $cap = ConvertTo-IdleCapabilityIdentifier -Value $c
                if ($null -eq $cap) {
                    continue
                }

                if (-not (Test-IdleCapabilityIdentifier -Capability $cap)) {
                    throw [System.ArgumentException]::new(
                        "$SourceName entry for step type '$StepType' declares invalid capability '$cap'. Expected dot-separated segments like 'IdLE.Identity.Read'.",
                        'Providers'
                    )
                }
            }
            return
        }

        throw [System.ArgumentException]::new(
            "$SourceName entry for step type '$StepType' has invalid RequiredCapabilities value. Expected string or string array.",
            'Providers'
        )
    }

    # Helper: Validate metadata contains no ScriptBlocks (wrapper around Assert-IdleNoScriptBlock).
    function Assert-IdleStepMetadataNoScriptBlock {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [AllowNull()]
            [object] $Value,

            [Parameter(Mandatory)]
            [string] $Path,

            [Parameter(Mandatory)]
            [string] $StepType,

            [Parameter(Mandatory)]
            [string] $SourceName
        )

        try {
            Assert-IdleNoScriptBlock -InputObject $Value -Path $Path
        }
        catch {
            # Rethrow with metadata-specific error message
            throw [System.ArgumentException]::new(
                "$SourceName entry for step type '$StepType' contains a ScriptBlock at '$Path'. ScriptBlocks are not allowed (data-only boundary).",
                'Providers'
            )
        }
    }

    # Helper: Get host-provided StepMetadata if available.
    function Get-IdleHostStepMetadata {
        [CmdletBinding()]
        param(
            [Parameter()]
            [AllowNull()]
            [object] $Providers
        )

        if ($null -eq $Providers) {
            return $null
        }

        if ($Providers -is [hashtable] -and $Providers.ContainsKey('StepMetadata')) {
            return $Providers['StepMetadata']
        }

        if ($Providers.PSObject.Properties.Name -contains 'StepMetadata') {
            return $Providers.StepMetadata
        }

        return $null
    }

    # Helper: Discover loaded step packs exporting Get-IdleStepMetadataCatalog.
    function Get-IdleStepPackModules {
        [CmdletBinding()]
        param()

        $loadedModules = Get-Module -Name 'IdLE.Steps.*' -All
        if ($null -eq $loadedModules) {
            return @()
        }

        $stepPackModules = @()
        foreach ($m in @($loadedModules)) {
            if ($null -ne $m.ExportedCommands -and $m.ExportedCommands.ContainsKey('Get-IdleStepMetadataCatalog')) {
                $stepPackModules += $m
            }
        }

        # Sort by module name for deterministic order
        return @($stepPackModules | Sort-Object -Property Name)
    }

    # Helper: Merge step pack catalog with duplicate detection.
    function Merge-IdleStepPackCatalog {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [hashtable] $Target,

            [Parameter(Mandatory)]
            [hashtable] $Source,

            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $SourceModuleName,

            [Parameter(Mandatory)]
            [hashtable] $StepTypeOwners
        )

        foreach ($key in $Source.Keys) {
            if ($null -eq $key -or [string]::IsNullOrWhiteSpace([string]$key)) {
                throw [System.ArgumentException]::new("$SourceModuleName contains an empty step type key.", 'Providers')
            }

            $value = $Source[$key]

            if ($value -isnot [hashtable]) {
                throw [System.ArgumentException]::new(
                    "$SourceModuleName entry for step type '$key' must be a hashtable (metadata object).",
                    'Providers'
                )
            }

            # Validate metadata shape (data-only, no ScriptBlocks).
            foreach ($metaKey in $value.Keys) {
                $metaValue = $value[$metaKey]

                # Recursively validate no ScriptBlocks anywhere in metadata
                Assert-IdleStepMetadataNoScriptBlock -Value $metaValue -Path $metaKey -StepType $key -SourceName $SourceModuleName

                if ($metaKey -eq 'RequiredCapabilities') {
                    Test-IdleRequiredCapabilities -Value $metaValue -StepType $key -SourceName $SourceModuleName
                }
            }

            # Validate WithSchema is present and structurally valid
            $withSchemaValue = if ($value.ContainsKey('WithSchema')) { $value['WithSchema'] } else { $null }
            Test-IdleWithSchema -Value $withSchemaValue -StepType $key -SourceName $SourceModuleName

            # Check for duplicates across step packs
            if ($StepTypeOwners.ContainsKey([string]$key)) {
                $existingOwner = $StepTypeOwners[[string]$key]
                $errorMessage = "DuplicateStepTypeMetadata: Step type '$key' is defined in both '$existingOwner' and '$SourceModuleName'. " + `
                    "Step packs must own unique step types."
                throw [System.InvalidOperationException]::new($errorMessage)
            }

            # Register ownership and add to catalog
            $StepTypeOwners[[string]$key] = $SourceModuleName
            $Target[[string]$key] = $value
        }
    }

    # 1) Discover and merge step pack catalogs (deterministic order).
    $stepTypeOwners = [hashtable]::new([System.StringComparer]::OrdinalIgnoreCase)
    $stepPackModules = Get-IdleStepPackModules

    foreach ($module in $stepPackModules) {
        $catalogFunction = $module.ExportedCommands['Get-IdleStepMetadataCatalog']
        if ($null -ne $catalogFunction) {
            $stepPackCatalog = & $catalogFunction
            if ($null -ne $stepPackCatalog -and $stepPackCatalog -is [hashtable]) {
                Merge-IdleStepPackCatalog -Target $catalog -Source $stepPackCatalog -SourceModuleName $module.Name -StepTypeOwners $stepTypeOwners
            }
        }
    }

    # 2) Apply host-provided StepMetadata as supplement-only (no overrides).
    $hostMetadata = Get-IdleHostStepMetadata -Providers $Providers

    if ($null -ne $hostMetadata) {
        if ($hostMetadata -isnot [hashtable]) {
            throw [System.ArgumentException]::new('Providers.StepMetadata must be a hashtable that maps Step.Type to a metadata object (hashtable).', 'Providers')
        }

        foreach ($key in $hostMetadata.Keys) {
            if ($null -eq $key -or [string]::IsNullOrWhiteSpace([string]$key)) {
                throw [System.ArgumentException]::new('Providers.StepMetadata contains an empty step type key.', 'Providers')
            }

            # Check if this step type already exists in step pack catalog (no override allowed)
            if ($catalog.ContainsKey([string]$key)) {
                $existingOwner = $stepTypeOwners[[string]$key]
                $errorMessage = "DuplicateStepTypeMetadata: Step type '$key' is already defined in step pack '$existingOwner'. " + `
                    "Host metadata (Providers.StepMetadata) can only supplement with new step types, not override existing ones."
                throw [System.InvalidOperationException]::new($errorMessage)
            }

            $value = $hostMetadata[$key]

            if ($value -isnot [hashtable]) {
                throw [System.ArgumentException]::new(
                    "Providers.StepMetadata entry for step type '$key' must be a hashtable (metadata object).",
                    'Providers'
                )
            }

            # Validate metadata shape (data-only, no ScriptBlocks).
            foreach ($metaKey in $value.Keys) {
                $metaValue = $value[$metaKey]

                # Recursively validate no ScriptBlocks anywhere in metadata
                Assert-IdleStepMetadataNoScriptBlock -Value $metaValue -Path $metaKey -StepType $key -SourceName 'Providers.StepMetadata'

                if ($metaKey -eq 'RequiredCapabilities') {
                    Test-IdleRequiredCapabilities -Value $metaValue -StepType $key -SourceName 'Providers.StepMetadata'
                }
            }

            # Validate WithSchema is present and structurally valid
            $withSchemaValue = if ($value.ContainsKey('WithSchema')) { $value['WithSchema'] } else { $null }
            Test-IdleWithSchema -Value $withSchemaValue -StepType $key -SourceName 'Providers.StepMetadata'

            # Add host supplement
            $catalog[[string]$key] = $value
            $stepTypeOwners[[string]$key] = 'Host'
        }
    }

    return $catalog
}

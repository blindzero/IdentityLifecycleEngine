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

        # Helper: Enforce capability namespaces (IdLE-defined or '<Owner>.IdLE.*').
        function Assert-IdleRequiredCapabilityNamespace {
            param([string] $Capability)

            $namespaceError = Get-IdleIdentifierNamespaceError -Kind 'Capability' -Identifier $Capability
            if ($null -ne $namespaceError) {
                throw [System.ArgumentException]::new(
                    "$namespaceError Declared by $SourceName entry for step type '$StepType'.",
                    'Providers'
                )
            }
        }

        if ($Value -is [string]) {
            $cap = ConvertTo-IdleCapabilityIdentifier -Value $Value
            if ($null -ne $cap -and -not (Test-IdleCapabilityIdentifier -Capability $cap)) {
                throw [System.ArgumentException]::new(
                    "$SourceName entry for step type '$StepType' declares invalid capability '$cap'. Expected dot-separated segments like 'IdLE.Identity.Read'.",
                    'Providers'
                )
            }
            if ($null -ne $cap) {
                Assert-IdleRequiredCapabilityNamespace -Capability $cap
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

                Assert-IdleRequiredCapabilityNamespace -Capability $cap
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

    # Helper: Validate a step pack 'Handler' value and bind it to the declaring module.
    function ConvertTo-IdleStepPackHandlerName {
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

        if ($Value -isnot [string] -or [string]::IsNullOrWhiteSpace($Value)) {
            throw [System.ArgumentException]::new(
                "$SourceName entry for step type '$StepType' has an invalid 'Handler'. Expected a non-empty function name (string) exported by '$SourceName', e.g. 'Invoke-MyStep' or '$SourceName\Invoke-MyStep'.",
                'Providers'
            )
        }

        $handler = $Value.Trim()

        # Unqualified names are bound to the declaring module so that a same-named function from another
        # module (or the global session) cannot take over the step type.
        if (-not $handler.Contains('\')) {
            return "$SourceName\$handler"
        }

        $parts = $handler.Split('\', 2)
        if ($parts[0] -ne $SourceName -or [string]::IsNullOrWhiteSpace($parts[1])) {
            throw [System.ArgumentException]::new(
                "$SourceName entry for step type '$StepType' declares Handler '$handler' outside of its own module. A step pack may only register its own commands, e.g. '$SourceName\Invoke-MyStep'.",
                'Providers'
            )
        }

        return $handler
    }

    # Helper: Return the step pack marker from a module manifest, or $null if the module is no step pack.
    # Marker shape: PrivateData = @{ IdLE = @{ Kind = 'StepPack'; StepCatalog = 'StepMetadataCatalog.psd1' } }
    function Get-IdleStepPackMarker {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [System.Management.Automation.PSModuleInfo] $Module
        )

        $privateData = $Module.PrivateData
        if ($privateData -isnot [hashtable] -or -not $privateData.ContainsKey('IdLE')) {
            return $null
        }

        $marker = $privateData['IdLE']
        if ($marker -isnot [hashtable] -or $marker['Kind'] -ne 'StepPack') {
            return $null
        }

        return $marker
    }

    # Helper: Load the catalog file declared by a step pack marker (data-only PSD1 inside the module).
    function Import-IdleStepPackCatalogFile {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [System.Management.Automation.PSModuleInfo] $Module,

            [Parameter(Mandatory)]
            [hashtable] $Marker
        )

        $relativePath = $Marker['StepCatalog']
        if ($relativePath -isnot [string] -or [string]::IsNullOrWhiteSpace($relativePath) -or [System.IO.Path]::IsPathRooted($relativePath)) {
            throw [System.ArgumentException]::new(
                "Step pack '$($Module.Name)' must declare PrivateData.IdLE.StepCatalog as a path relative to the module folder, e.g. 'StepMetadataCatalog.psd1'.",
                'Providers'
            )
        }

        # The catalog must ship with the module; paths escaping the module folder are rejected.
        $moduleBase = [System.IO.Path]::GetFullPath($Module.ModuleBase).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
        $catalogPath = [System.IO.Path]::GetFullPath((Join-Path -Path $moduleBase -ChildPath $relativePath))
        if (-not $catalogPath.StartsWith($moduleBase + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw [System.ArgumentException]::new(
                "Step pack '$($Module.Name)' declares StepCatalog '$relativePath' outside of its module folder.",
                'Providers'
            )
        }

        if (-not (Test-Path -LiteralPath $catalogPath -PathType Leaf)) {
            throw [System.ArgumentException]::new(
                "Step pack '$($Module.Name)' declares StepCatalog '$relativePath', but the file was not found at '$catalogPath'.",
                'Providers'
            )
        }

        $rawData = Import-PowerShellDataFile -LiteralPath $catalogPath

        $stepPackCatalog = [hashtable]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($key in $rawData.Keys) {
            $stepPackCatalog[$key] = $rawData[$key]
        }

        return $stepPackCatalog
    }

    # Helper: Discover loaded step packs by manifest marker (PrivateData.IdLE.Kind = 'StepPack').
    # Module names are never used for discovery or ownership.
    function Get-IdleStepPackModules {
        [CmdletBinding()]
        param()

        $stepPackModules = @()
        foreach ($m in @(Get-Module -All)) {
            if ($null -ne (Get-IdleStepPackMarker -Module $m)) {
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
            [hashtable] $StepTypeOwners,

            [Parameter()]
            [switch] $FirstParty
        )

        foreach ($key in $Source.Keys) {
            if ($null -eq $key -or [string]::IsNullOrWhiteSpace([string]$key)) {
                throw [System.ArgumentException]::new("$SourceModuleName contains an empty step type key.", 'Providers')
            }

            # Only first-party step packs may define 'IdLE.*' step types; extensions use '<Owner>.IdLE.Step.*'.
            $namespaceError = Get-IdleIdentifierNamespaceError -Kind 'StepType' -Identifier ([string]$key) -FirstParty:$FirstParty
            if ($null -ne $namespaceError) {
                throw [System.ArgumentException]::new("$namespaceError Defined by step pack '$SourceModuleName'.", 'Providers')
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

            # Validate WithSchema and Provider (typed With contract).
            Assert-IdleStepMetadataContract -Metadata $value -StepType $key -SourceName $SourceModuleName

            # Check for duplicates across step packs
            if ($StepTypeOwners.ContainsKey([string]$key)) {
                $existingOwner = $StepTypeOwners[[string]$key]
                $errorMessage = "DuplicateStepTypeMetadata: Step type '$key' is defined in both '$existingOwner' and '$SourceModuleName'. " + `
                    "Step packs must own unique step types."
                throw [System.InvalidOperationException]::new($errorMessage)
            }

            if ($value.ContainsKey('Handler')) {
                # Copy before normalizing so the step pack's own catalog object stays untouched.
                $value = $value.Clone()
                $value['Handler'] = ConvertTo-IdleStepPackHandlerName -Value $value['Handler'] -StepType $key -SourceName $SourceModuleName
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
        $stepPackCatalog = Import-IdleStepPackCatalogFile -Module $module -Marker (Get-IdleStepPackMarker -Module $module)

        if ($null -ne $stepPackCatalog -and $stepPackCatalog -is [hashtable]) {
            Merge-IdleStepPackCatalog -Target $catalog -Source $stepPackCatalog -SourceModuleName $module.Name -StepTypeOwners $stepTypeOwners -FirstParty:(Test-IdleFirstPartyModule -Module $module)
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

            # Host step types are extensions: '<Owner>.IdLE.Step.*'.
            $namespaceError = Get-IdleIdentifierNamespaceError -Kind 'StepType' -Identifier ([string]$key)
            if ($null -ne $namespaceError) {
                throw [System.ArgumentException]::new("$namespaceError Defined by Providers.StepMetadata.", 'Providers')
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

            # Validate WithSchema and Provider (typed With contract).
            Assert-IdleStepMetadataContract -Metadata $value -StepType $key -SourceName 'Providers.StepMetadata'

            # Host handlers are registered via Providers.StepRegistry only, so that execution does not depend on
            # the metadata passed at plan time.
            if ($value.ContainsKey('Handler')) {
                throw [System.ArgumentException]::new(
                    "Providers.StepMetadata entry for step type '$key' must not declare 'Handler'. Register host step handlers via Providers.StepRegistry['$key'].",
                    'Providers'
                )
            }

            # Add host supplement
            $catalog[[string]$key] = $value
            $stepTypeOwners[[string]$key] = 'Host'
        }
    }

    return $catalog
}

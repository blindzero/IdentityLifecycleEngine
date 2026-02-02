<#
.SYNOPSIS
Creates IdLE module package(s) suitable for publishing or distribution.

.DESCRIPTION
Supports two packaging modes:

1. Bundled (default): Creates a single self-contained IdLE package with nested modules under 'Modules/'.
   This is the legacy format for backwards compatibility.

2. MultiModule: Creates separate packages for each module, suitable for publishing each module
   independently to PowerShell Gallery. Transforms IdLE manifest (NestedModules → RequiredModules,
   removes ScriptsToProcess).

.PARAMETER Mode
Packaging mode: 'Bundled' (default, legacy single package) or 'MultiModule' (separate packages per module).

.PARAMETER RepoRootPath
Repository root path. Defaults to the parent folder of this script directory.

.PARAMETER OutputDirectory
Target folder for package(s). 
- Bundled mode: Defaults to '<RepoRootPath>/artifacts/IdLE'
- MultiModule mode: Defaults to '<RepoRootPath>/artifacts/modules' (one subdirectory per module)

.PARAMETER ModuleNames
(MultiModule mode only) Names of modules to package. Defaults to all IdLE modules under src/.

.PARAMETER NestedModuleNames
(Bundled mode only) Names of nested modules to auto-import when IdLE is imported.

.PARAMETER IncludeModuleNames
(Bundled mode only) Names of all modules to include in the package under 'Modules/'.

.PARAMETER Clean
If set, deletes the OutputDirectory before staging the package.

.OUTPUTS
System.IO.DirectoryInfo or System.IO.DirectoryInfo[]

.EXAMPLE
# Legacy bundled package
pwsh -NoProfile -File ./tools/New-IdleModulePackage.ps1

.EXAMPLE
# Multi-module packages for PSGallery
pwsh -NoProfile -File ./tools/New-IdleModulePackage.ps1 -Mode MultiModule -Clean

.EXAMPLE
# Package specific modules only
pwsh -NoProfile -File ./tools/New-IdleModulePackage.ps1 -Mode MultiModule -ModuleNames 'IdLE','IdLE.Core'
#>

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateSet('Bundled', 'MultiModule')]
    [string] $Mode = 'Bundled',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string] $RepoRootPath = (Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')).Path,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string] $OutputDirectory,

    [Parameter()]
    [string[]] $ModuleNames = $null,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string[]] $NestedModuleNames = @(
        'IdLE.Core',
        'IdLE.Steps.Common'
    ),

    [Parameter()]
    [string[]] $IncludeModuleNames = $null,

    [Parameter()]
    [switch] $Clean
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Default IncludeModuleNames to all batteries-included modules if not specified
if ($null -eq $IncludeModuleNames -or $IncludeModuleNames.Count -eq 0) {
    $IncludeModuleNames = @(
        'IdLE.Core',
        'IdLE.Steps.Common',
        'IdLE.Steps.DirectorySync',
        'IdLE.Steps.Mailbox',
        'IdLE.Provider.AD',
        'IdLE.Provider.EntraID',
        'IdLE.Provider.ExchangeOnline',
        'IdLE.Provider.DirectorySync.EntraConnect'
    )
}

function Resolve-IdleRepoRoot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    $resolved = (Resolve-Path -LiteralPath $Path).Path

    $idleManifest = Join-Path -Path $resolved -ChildPath 'src/IdLE/IdLE.psd1'
    if (-not (Test-Path -LiteralPath $idleManifest)) {
        throw "RepoRootPath does not look like the IdLE repository root (missing 'src/IdLE/IdLE.psd1'): $resolved"
    }

    return $resolved
}

function Initialize-IdleDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter()]
        [switch] $ForceClean
    )

    if ($ForceClean -and (Test-Path -LiteralPath $Path)) {
        Remove-Item -LiteralPath $Path -Recurse -Force
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -ItemType Directory -Force | Out-Null
    }
}

function Copy-IdleModuleFolder {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $SourcePath,

        [Parameter(Mandatory)]
        [string] $DestinationPath
    )

    if (-not (Test-Path -LiteralPath $SourcePath)) {
        throw "Source module folder not found: $SourcePath"
    }

    Initialize-IdleDirectory -Path $DestinationPath

    # Copy content of the module folder, not the folder itself, to keep predictable structure.
    Copy-Item -Path (Join-Path -Path $SourcePath -ChildPath '*') -Destination $DestinationPath -Recurse -Force
}

function Get-IdleNestedModuleEntryPaths {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]] $Names
    )

    $paths = foreach ($n in $Names) {
        # NestedModules should reference the nested module manifests relative to the *IdLE* manifest folder.
        ".\Modules\$n\$n.psd1"
    }

    return , $paths
}

function Set-IdleNestedModulesInManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ManifestPath,

        [Parameter(Mandatory)]
        [string[]] $NestedModuleEntryPaths
    )

    if (-not (Test-Path -LiteralPath $ManifestPath)) {
        throw "Manifest not found: $ManifestPath"
    }

    $raw = Get-Content -LiteralPath $ManifestPath -Raw -ErrorAction Stop

    $indent = '    '
    $entries = ($NestedModuleEntryPaths | ForEach-Object { "$indent$indent'$_'" }) -join ",`n"

    $replacement = @"
${indent}NestedModules = @(
$entries
${indent})
"@

    # Replace an existing NestedModules block.
    # This intentionally keeps the rest of the manifest formatting intact.
    $pattern = '(?ms)^[ \t]*NestedModules[ \t]*=[ \t]*@\((?:.|\n)*?\)[ \t]*\r?\n'
    if ($raw -match $pattern) {
        $updated = [regex]::Replace($raw, $pattern, "$replacement`r`n", 1)
    }
    else {
        # If NestedModules is missing, insert it after RootModule (or near the top).
        $insertAfter = '(?m)^[ \t]*RootModule[ \t]*=.*\r?\n'
        if ($raw -match $insertAfter) {
            $updated = [regex]::Replace($raw, $insertAfter, '$0' + "$replacement`r`n", 1)
        }
        else {
            $updated = "$replacement`r`n$raw"
        }
    }

    Set-Content -LiteralPath $ManifestPath -Value $updated -Encoding UTF8 -NoNewline
}

#region MultiModule Mode Functions

function Get-IdleModuleFolders {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $SrcPath
    )

    $modules = Get-ChildItem -Path $SrcPath -Directory | Where-Object {
        $manifestPath = Join-Path -Path $_.FullName -ChildPath "$($_.Name).psd1"
        Test-Path -LiteralPath $manifestPath
    }

    return $modules
}

function Convert-IdleManifestForPublication {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ManifestPath,

        [Parameter(Mandatory)]
        [string] $ModuleName
    )

    if (-not (Test-Path -LiteralPath $ManifestPath)) {
        throw "Manifest not found: $ManifestPath"
    }

    Write-Host "  Converting manifest for publication..."
    
    $raw = Get-Content -LiteralPath $ManifestPath -Raw -ErrorAction Stop

    # IdLE meta-module transformations
    if ($ModuleName -eq 'IdLE') {
        # Extract current NestedModules to convert to RequiredModules
        # Entries look like: '..\IdLE.Core\IdLE.Core.psd1'
        # We want to extract: 'IdLE.Core'
        $requiredModules = @()
        
        # Pattern: match ..\ followed by module name followed by \ again
        if ($raw -match '\.\.\\(IdLE\.[^\\]+)\\') {
            # Extract all unique module names
            $allMatches = [regex]::Matches($raw, '\.\.\\(IdLE\.([^\\]+))\\')
            foreach ($match in $allMatches) {
                $moduleName = $match.Groups[1].Value  # Group 1 is the full IdLE.ModuleName
                if ($requiredModules -notcontains $moduleName) {
                    $requiredModules += $moduleName
                }
            }
        }
        
        if ($requiredModules.Count -gt 0) {
            # Build RequiredModules block
            $indent = '    '
            $entries = ($requiredModules | ForEach-Object { "$indent$indent'$_'" }) -join ",`n"
            $requiredModulesBlock = @"
${indent}RequiredModules = @(
$entries
${indent})
"@
            
            # Replace NestedModules with RequiredModules
            $raw = [regex]::Replace($raw, '(?ms)^[ \t]*NestedModules[ \t]*=[ \t]*@\((?:.|\n)*?\)[ \t]*\r?\n', "$requiredModulesBlock`r`n", 1)
            Write-Host "    - Converted NestedModules to RequiredModules: $($requiredModules -join ', ')"
        }

        # Remove ScriptsToProcess (not needed when modules are in standard PSModulePath)
        $scriptsPattern = '(?ms)^[ \t]*ScriptsToProcess[ \t]*=[ \t]*@\([^\)]*\)[ \t]*\r?\n'
        if ($raw -match $scriptsPattern) {
            $raw = [regex]::Replace($raw, $scriptsPattern, '', 1)
            Write-Host "    - Removed ScriptsToProcess"
        }

        # Remove Init.ps1 file from package since it's not needed for published modules
        $initPath = Join-Path -Path (Split-Path -Path $ManifestPath -Parent) -ChildPath 'IdLE.Init.ps1'
        if (Test-Path -LiteralPath $initPath) {
            Remove-Item -LiteralPath $initPath -Force
            Write-Host "    - Removed IdLE.Init.ps1"
        }
    }

    # Save modified manifest
    Set-Content -LiteralPath $ManifestPath -Value $raw -Encoding UTF8 -NoNewline
}

function New-IdleMultiModulePackages {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $RepoRootPath,

        [Parameter(Mandatory)]
        [string] $OutputDirectory,

        [Parameter()]
        [string[]] $ModuleNames,

        [Parameter()]
        [switch] $Clean
    )

    $srcRoot = Join-Path -Path $RepoRootPath -ChildPath 'src'

    Write-Host "Multi-Module Packaging for PSGallery Publication"
    Write-Host "=================================================="
    Write-Host "Repository Root: $RepoRootPath"
    Write-Host "Output Directory: $OutputDirectory"
    Write-Host ""

    # Determine modules to package
    if ($null -eq $ModuleNames -or $ModuleNames.Count -eq 0) {
        $moduleFolders = Get-IdleModuleFolders -SrcPath $srcRoot
        $ModuleNames = $moduleFolders.Name
        Write-Host "Auto-discovered modules: $($ModuleNames -join ', ')"
    }
    else {
        Write-Host "Packaging specified modules: $($ModuleNames -join ', ')"
    }

    Write-Host ""

    # Initialize output directory
    Initialize-IdleDirectory -Path $OutputDirectory -ForceClean:$Clean

    # Package each module
    $packagedModules = @()

    foreach ($moduleName in $ModuleNames) {
        Write-Host "Packaging: $moduleName"
        Write-Host "---"
        
        $moduleSrc = Join-Path -Path $srcRoot -ChildPath $moduleName
        $moduleDst = Join-Path -Path $OutputDirectory -ChildPath $moduleName

        if (-not (Test-Path -LiteralPath $moduleSrc)) {
            Write-Warning "  Module source not found, skipping: $moduleSrc"
            continue
        }

        # Copy module to output
        Write-Host "  Copying module content..."
        Copy-IdleModuleFolder -SourcePath $moduleSrc -DestinationPath $moduleDst

        # Transform manifest for publication
        $manifestPath = Join-Path -Path $moduleDst -ChildPath "$moduleName.psd1"
        Convert-IdleManifestForPublication -ManifestPath $manifestPath -ModuleName $moduleName

        Write-Host "  ✓ Manifest transformed for publication"

        $packagedModules += Get-Item -LiteralPath $moduleDst
        Write-Host ""
    }

    Write-Host "=================================================="
    Write-Host "Successfully packaged $($packagedModules.Count) module(s)"
    Write-Host "Output location: $OutputDirectory"
    Write-Host ""

    return $packagedModules
}

#endregion

#region Main Execution Logic

# Resolve repository root
$RepoRootPath = Resolve-IdleRepoRoot -Path $RepoRootPath

# Set default output directory based on mode
if (-not $PSBoundParameters.ContainsKey('OutputDirectory')) {
    if ($Mode -eq 'MultiModule') {
        $OutputDirectory = Join-Path -Path $RepoRootPath -ChildPath 'artifacts/modules'
    }
    else {
        $OutputDirectory = Join-Path -Path $RepoRootPath -ChildPath 'artifacts/IdLE'
    }
}

# Execute appropriate packaging mode
if ($Mode -eq 'MultiModule') {
    # Multi-module packaging for PSGallery
    $result = New-IdleMultiModulePackages `
        -RepoRootPath $RepoRootPath `
        -OutputDirectory $OutputDirectory `
        -ModuleNames $ModuleNames `
        -Clean:$Clean
    
    return $result
}
else {
    # Bundled packaging (legacy)
    
    # Default IncludeModuleNames to all batteries-included modules if not specified
    if ($null -eq $IncludeModuleNames -or $IncludeModuleNames.Count -eq 0) {
        # Load module list from publish order configuration (required - single source of truth)
        $publishOrderPath = Join-Path -Path $PSScriptRoot -ChildPath 'ModulePublishOrder.psd1'
        if (-not (Test-Path $publishOrderPath)) {
            throw @"
ModulePublishOrder.psd1 not found at '$publishOrderPath'.
This file is required as the single source of truth for module packaging order.
Expected location: tools/ModulePublishOrder.psd1 (relative to repository root)
See docs/develop/releases.md for more information.
"@
        }
        
        $publishOrderConfig = Import-PowerShellDataFile -Path $publishOrderPath
        # Use all modules except IdLE itself (meta-module is the package root, not nested)
        $IncludeModuleNames = $publishOrderConfig.PublishOrder | Where-Object { $_ -ne 'IdLE' }
    }

    $srcRoot = Join-Path -Path $RepoRootPath -ChildPath 'src'
    $idleSrc = Join-Path -Path $srcRoot -ChildPath 'IdLE'
    $idleDst = $OutputDirectory
    $modulesDst = Join-Path -Path $idleDst -ChildPath 'Modules'

    Initialize-IdleDirectory -Path $idleDst -ForceClean:$Clean

    # 1) Stage meta-module IdLE (top-level package root)
    Copy-IdleModuleFolder -SourcePath $idleSrc -DestinationPath $idleDst

    # 2) Stage nested modules into IdLE/Modules/<ModuleName>/
    Initialize-IdleDirectory -Path $modulesDst

    foreach ($name in $IncludeModuleNames) {
        $nestedSrc = Join-Path -Path $srcRoot -ChildPath $name
        $nestedDst = Join-Path -Path $modulesDst -ChildPath $name

        Copy-IdleModuleFolder -SourcePath $nestedSrc -DestinationPath $nestedDst
    }

    # 3) Patch staged manifest to reference in-package nested module manifests (auto-imported)
    $stagedManifest = Join-Path -Path $idleDst -ChildPath 'IdLE.psd1'
    $nestedEntries = Get-IdleNestedModuleEntryPaths -Names $NestedModuleNames
    Set-IdleNestedModulesInManifest -ManifestPath $stagedManifest -NestedModuleEntryPaths $nestedEntries

    return Get-Item -LiteralPath $idleDst
}

#endregion

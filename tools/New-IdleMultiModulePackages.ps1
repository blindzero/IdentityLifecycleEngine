<#
.SYNOPSIS
Creates separate module packages for multi-module PSGallery publishing.

.DESCRIPTION
Produces one installable module package per module under src/, suitable for publishing each
module separately to PowerShell Gallery.

Key transformations for published manifests:
- IdLE meta-module: Converts NestedModules → RequiredModules (name-based)
- IdLE meta-module: Removes ScriptsToProcess (not needed when modules are in PSModulePath)
- All modules: Preserves their existing name-based RequiredModules
- All modules: Validates and prepares for independent publication

.PARAMETER RepoRootPath
Repository root path. Defaults to the parent folder of this script directory.

.PARAMETER OutputDirectory
Target folder for all module packages. Defaults to '<RepoRootPath>/artifacts/modules'.
Each module will be placed in a subdirectory: <OutputDirectory>/<ModuleName>/

.PARAMETER ModuleNames
Names of modules to package. Defaults to all IdLE modules under src/.

.PARAMETER Clean
If set, deletes the OutputDirectory before creating packages.

.OUTPUTS
System.IO.DirectoryInfo[]

.EXAMPLE
pwsh -NoProfile -File ./tools/New-IdleMultiModulePackages.ps1

.EXAMPLE
pwsh -NoProfile -File ./tools/New-IdleMultiModulePackages.ps1 -Clean

.EXAMPLE
pwsh -NoProfile -File ./tools/New-IdleMultiModulePackages.ps1 -ModuleNames 'IdLE','IdLE.Core'
#>

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string] $RepoRootPath = (Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')).Path,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string] $OutputDirectory,

    [Parameter()]
    [string[]] $ModuleNames = $null,

    [Parameter()]
    [switch] $Clean
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#region Helper Functions

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
        Write-Host "Cleaning output directory: $Path"
        Remove-Item -LiteralPath $Path -Recurse -Force
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -ItemType Directory -Force | Out-Null
    }
}

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

function Copy-IdleModulePackage {
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

    Write-Host "  Copying module content..."
    Copy-Item -Path (Join-Path -Path $SourcePath -ChildPath '*') -Destination $DestinationPath -Recurse -Force
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
        
        # Simple pattern: match ..\ followed by module name followed by \ again
        # Pattern: ..\(IdLE.ModuleName)\ModuleName.psd1
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

#endregion

#region Main Script

# Resolve paths
$RepoRootPath = Resolve-IdleRepoRoot -Path $RepoRootPath
$srcRoot = Join-Path -Path $RepoRootPath -ChildPath 'src'

if (-not $PSBoundParameters.ContainsKey('OutputDirectory')) {
    $OutputDirectory = Join-Path -Path $RepoRootPath -ChildPath 'artifacts/modules'
}

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
    Copy-IdleModulePackage -SourcePath $moduleSrc -DestinationPath $moduleDst

    # Transform manifest for publication
    $manifestPath = Join-Path -Path $moduleDst -ChildPath "$moduleName.psd1"
    Convert-IdleManifestForPublication -ManifestPath $manifestPath -ModuleName $moduleName

    # Note: We skip Test-ModuleManifest validation because RequiredModules may reference
    # modules not yet in PSModulePath (they'll be published separately to PSGallery)
    Write-Host "  ✓ Manifest transformed for publication"

    $packagedModules += Get-Item -LiteralPath $moduleDst
    Write-Host ""
}

Write-Host "=================================================="
Write-Host "Successfully packaged $($packagedModules.Count) module(s)"
Write-Host "Output location: $OutputDirectory"
Write-Host ""

# Return packaged module directories
return $packagedModules

#endregion

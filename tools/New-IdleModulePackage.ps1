<#
.SYNOPSIS
Creates a self-contained IdLE module package folder suitable for publishing (or other distribution).

.DESCRIPTION
Builds a staging folder that contains the meta-module 'IdLE' and its nested modules
(e.g. IdLE.Core, IdLE.Steps.Common, IdLE.Provider.Mock) under a local 'Modules/' folder.

This avoids restructuring the repository while still producing a PowerShell Gallery compatible layout.

The script copies sources into an output folder and patches the staged IdLE.psd1 so that
NestedModules use in-package relative paths (.\Modules\...\*.psd1) instead of repo paths (..\*).

.PARAMETER RepoRootPath
Repository root path. Defaults to the parent folder of this script directory.

.PARAMETER OutputDirectory
Target folder for the staged package. Defaults to '<RepoRootPath>/artifacts/IdLE'.

.PARAMETER NestedModuleNames
Names of nested modules to include under 'Modules/'. Defaults to IdLE.Core, IdLE.Steps.Common,
and IdLE.Provider.Mock.

.PARAMETER Clean
If set, deletes the OutputDirectory before staging the package.

.OUTPUTS
System.IO.DirectoryInfo

.EXAMPLE
pwsh -NoProfile -File ./tools/New-IdleModulePackage.ps1

.EXAMPLE
pwsh -NoProfile -File ./tools/New-IdleModulePackage.ps1 -OutputDirectory ./artifacts/IdLE -Clean
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
    [ValidateNotNullOrEmpty()]
    [string[]] $NestedModuleNames = @(
        'IdLE.Core',
        'IdLE.Steps.Common',
        'IdLE.Provider.Mock'
    ),

    [Parameter()]
    [switch] $Clean
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

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

    return ,$paths
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

# Defaults
$RepoRootPath = Resolve-IdleRepoRoot -Path $RepoRootPath

if (-not $PSBoundParameters.ContainsKey('OutputDirectory')) {
    $OutputDirectory = Join-Path -Path $RepoRootPath -ChildPath 'artifacts/IdLE'
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

foreach ($name in $NestedModuleNames) {
    $nestedSrc = Join-Path -Path $srcRoot -ChildPath $name
    $nestedDst = Join-Path -Path $modulesDst -ChildPath $name

    Copy-IdleModuleFolder -SourcePath $nestedSrc -DestinationPath $nestedDst
}

# 3) Patch staged manifest to reference in-package nested module manifests
$stagedManifest = Join-Path -Path $idleDst -ChildPath 'IdLE.psd1'
$nestedEntries = Get-IdleNestedModuleEntryPaths -Names $NestedModuleNames
Set-IdleNestedModulesInManifest -ManifestPath $stagedManifest -NestedModuleEntryPaths $nestedEntries

Get-Item -LiteralPath $idleDst

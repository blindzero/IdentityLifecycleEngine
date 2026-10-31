<#
.SYNOPSIS
Creates the bundled IdLE module package suitable for publishing or distribution.

.DESCRIPTION
Creates a single self-contained 'IdLE' package. All first-party modules are staged as nested
modules under 'Modules/<Name>/' and are imported together with IdLE.

The bundle content is defined by the NestedModules entries of 'src/IdLE/IdLE.psd1'
(single source of truth). In the source manifest these entries point to the sibling module
folders under 'src/' ('..\<Name>\<Name>.psd1'); in the staged manifest they are rewritten to
'.\Modules\<Name>\<Name>.psd1'.

.PARAMETER RepoRootPath
Repository root path. Defaults to the parent folder of this script directory.

.PARAMETER OutputDirectory
Target folder for the package. Defaults to '<RepoRootPath>/artifacts/IdLE'.

.PARAMETER Clean
If set, deletes the OutputDirectory before staging the package.

.OUTPUTS
System.IO.DirectoryInfo

.EXAMPLE
# Bundled package for PSGallery publishing
pwsh -NoProfile -File ./tools/New-IdleModulePackage.ps1 -Clean

.EXAMPLE
# Stage the package to a custom folder
pwsh -NoProfile -File ./tools/New-IdleModulePackage.ps1 -OutputDirectory ./out/IdLE -Clean
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

function Get-IdleBundledModuleNames {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ManifestPath
    )

    $manifest = Import-PowerShellDataFile -LiteralPath $ManifestPath

    $names = foreach ($entry in @($manifest.NestedModules)) {
        # Source entries must reference sibling module folders: '..\<Name>\<Name>.psd1'
        if ([string]$entry -notmatch '^\.\.\\(?<Name>[^\\]+)\\(?<File>[^\\]+)\.psd1$' -or $Matches.Name -ne $Matches.File) {
            throw "Unexpected NestedModules entry in '$ManifestPath': '$entry'. Expected '..\<Name>\<Name>.psd1'."
        }

        $Matches.Name
    }

    if (@($names).Count -eq 0) {
        throw "No NestedModules found in '$ManifestPath'. The bundle content is defined by this list."
    }

    return , @($names)
}

function Set-IdleBundledNestedModulesInManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ManifestPath,

        [Parameter(Mandatory)]
        [string[]] $ModuleNames
    )

    $raw = Get-Content -LiteralPath $ManifestPath -Raw -ErrorAction Stop

    # Rewrite each entry in place to keep the rest of the manifest formatting intact.
    foreach ($name in $ModuleNames) {
        $escaped = [regex]::Escape($name)
        $pattern = "'\.\.\\$escaped\\$escaped\.psd1'"
        if ($raw -notmatch $pattern) {
            throw "NestedModules entry for '$name' not found in staged manifest: $ManifestPath"
        }

        $raw = [regex]::Replace($raw, $pattern, "'.\Modules\$name\$name.psd1'")
    }

    Set-Content -LiteralPath $ManifestPath -Value $raw -Encoding UTF8 -NoNewline
}

# Resolve repository root
$RepoRootPath = Resolve-IdleRepoRoot -Path $RepoRootPath

if (-not $PSBoundParameters.ContainsKey('OutputDirectory')) {
    $OutputDirectory = Join-Path -Path $RepoRootPath -ChildPath 'artifacts/IdLE'
}

$srcRoot = Join-Path -Path $RepoRootPath -ChildPath 'src'
$idleSrc = Join-Path -Path $srcRoot -ChildPath 'IdLE'
$idleDst = $OutputDirectory
$modulesDst = Join-Path -Path $idleDst -ChildPath 'Modules'

$moduleNames = Get-IdleBundledModuleNames -ManifestPath (Join-Path -Path $idleSrc -ChildPath 'IdLE.psd1')

Initialize-IdleDirectory -Path $idleDst -ForceClean:$Clean

# 1) Stage IdLE (package root)
Copy-IdleModuleFolder -SourcePath $idleSrc -DestinationPath $idleDst

# 2) Stage bundled modules into IdLE/Modules/<ModuleName>/
Initialize-IdleDirectory -Path $modulesDst

foreach ($name in $moduleNames) {
    $nestedSrc = Join-Path -Path $srcRoot -ChildPath $name
    $nestedDst = Join-Path -Path $modulesDst -ChildPath $name

    Copy-IdleModuleFolder -SourcePath $nestedSrc -DestinationPath $nestedDst
}

# 3) Patch staged manifest to reference the in-package nested module manifests
$stagedManifest = Join-Path -Path $idleDst -ChildPath 'IdLE.psd1'
Set-IdleBundledNestedModulesInManifest -ManifestPath $stagedManifest -ModuleNames $moduleNames

return Get-Item -LiteralPath $idleDst

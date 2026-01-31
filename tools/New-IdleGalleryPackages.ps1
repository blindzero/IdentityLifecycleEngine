<#
.SYNOPSIS
Packages IdLE modules separately for PowerShell Gallery publishing.

.DESCRIPTION
Creates individual module packages in artifacts/modules/ folder, with each module
in its own subdirectory. For the IdLE meta-module, transforms the manifest to use
RequiredModules instead of NestedModules for Gallery compatibility.

.PARAMETER RepoRootPath
Repository root path. Defaults to the parent folder of this script directory.

.PARAMETER OutputDirectory
Target folder for packages. Defaults to '<RepoRootPath>/artifacts/modules'.

.PARAMETER Clean
If set, deletes the OutputDirectory before packaging.

.OUTPUTS
System.IO.DirectoryInfo[]

.EXAMPLE
pwsh -NoProfile -File ./tools/New-IdleGalleryPackages.ps1 -Clean

.EXAMPLE
$packages = & ./tools/New-IdleGalleryPackages.ps1
$packages | ForEach-Object { Write-Host "Packaged: $($_.Name)" }
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

# Defaults
if (-not $PSBoundParameters.ContainsKey('OutputDirectory')) {
    $OutputDirectory = Join-Path -Path $RepoRootPath -ChildPath 'artifacts/modules'
}

$srcRoot = Join-Path -Path $RepoRootPath -ChildPath 'src'
if (-not (Test-Path -LiteralPath $srcRoot)) {
    throw "Source folder not found: $srcRoot"
}

# Clean output directory if requested
if ($Clean -and (Test-Path -LiteralPath $OutputDirectory)) {
    Remove-Item -LiteralPath $OutputDirectory -Recurse -Force
}

if (-not (Test-Path -LiteralPath $OutputDirectory)) {
    New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null
}

# Get all publishable modules
$modules = Get-ChildItem -Path $srcRoot -Directory |
    Where-Object {
        $manifestPath = Join-Path -Path $_.FullName -ChildPath "$($_.Name).psd1"
        Test-Path -LiteralPath $manifestPath
    }

$packaged = New-Object System.Collections.Generic.List[System.IO.DirectoryInfo]

foreach ($moduleDir in $modules) {
    $moduleName = $moduleDir.Name
    $moduleSrc = $moduleDir.FullName
    $moduleDst = Join-Path -Path $OutputDirectory -ChildPath $moduleName

    Write-Host "Packaging: $moduleName"

    # Copy module files
    if (Test-Path -LiteralPath $moduleDst) {
        Remove-Item -LiteralPath $moduleDst -Recurse -Force
    }
    New-Item -Path $moduleDst -ItemType Directory -Force | Out-Null
    Copy-Item -Path (Join-Path -Path $moduleSrc -ChildPath '*') -Destination $moduleDst -Recurse -Force

    # Transform IdLE meta-module manifest for Gallery
    if ($moduleName -eq 'IdLE') {
        $manifestPath = Join-Path -Path $moduleDst -ChildPath 'IdLE.psd1'
        $content = Get-Content -Path $manifestPath -Raw

        # Read version from manifest
        $data = Import-PowerShellDataFile -LiteralPath $manifestPath
        $version = $data.ModuleVersion

        if ($content -match '(?ms)^\s*NestedModules\s*=') {
            Write-Verbose "Transforming IdLE manifest for PowerShell Gallery"

            # Build RequiredModules block
            $requiredModules = @"
    RequiredModules = @(
        @{ ModuleName = 'IdLE.Core'; ModuleVersion = '$version' },
        @{ ModuleName = 'IdLE.Steps.Common'; ModuleVersion = '$version' }
    )
"@

            # Remove NestedModules block
            $pattern = '(?ms)^[ \t]*NestedModules[ \t]*=[ \t]*@\([\s\S]*?\)[ \t]*\r?\n'
            $updated = [regex]::Replace($content, $pattern, '')

            # Add RequiredModules after ScriptsToProcess or RootModule
            $insertAfter = '(?m)^[ \t]*ScriptsToProcess[ \t]*=.*\)[ \t]*\r?\n'
            if ($updated -match $insertAfter) {
                $updated = [regex]::Replace($updated, $insertAfter, "`$0`r`n$requiredModules`r`n", 1)
            }
            else {
                $insertAfter = '(?m)^[ \t]*RootModule[ \t]*=.*\r?\n'
                if ($updated -match $insertAfter) {
                    $updated = [regex]::Replace($updated, $insertAfter, "`$0`r`n$requiredModules`r`n", 1)
                }
            }

            Set-Content -Path $manifestPath -Value $updated -Encoding UTF8 -NoNewline
        }
    }

    $packaged.Add((Get-Item -LiteralPath $moduleDst))
}

Write-Host ""
Write-Host "Packaged $($packaged.Count) module(s) to: $OutputDirectory"
$packaged | ForEach-Object { Write-Host "  - $($_.Name)" }

return , $packaged.ToArray()

<#
.SYNOPSIS
    Sets ModuleVersion in IdLE module manifests under ./src to a target version.

.DESCRIPTION
    This script searches for PowerShell module manifest files (*.psd1) under the repository's "src" folder
    and updates the "ModuleVersion" field to the provided target version.

    The script is intended for release preparation (e.g., bumping all shipped modules to v0.2.0).
    It is designed to be deterministic, safe to run multiple times (idempotent), and to support -WhatIf/-Confirm.

.PARAMETER TargetVersion
    The version string to set as ModuleVersion (e.g., 0.2.0 or 0.2.0.0).

.PARAMETER RepoRootPath
    The repository root path. Defaults to the parent directory of the script folder (../).

.PARAMETER IncludeAllPsd1
    If set, searches all *.psd1 under ./src recursively.
    If not set (default), the script only updates manifests that match the pattern ./src/<ModuleName>/<ModuleName>.psd1.

.PARAMETER CreateBackup
    If set, creates a .bak copy next to each modified manifest before changing it.

.EXAMPLE
    PS> pwsh -NoProfile -File ./tools/Set-IdleModuleVersion.ps1 -TargetVersion 0.2.0 -WhatIf

.EXAMPLE
    PS> pwsh -NoProfile -File ./tools/Set-IdleModuleVersion.ps1 -TargetVersion 0.2.0 -CreateBackup

.NOTES
    - The script uses a conservative regex replace for the ModuleVersion line.
    - It does not attempt to parse PSD1 into a hashtable, to avoid formatting churn.
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^\d+\.\d+\.\d+(\.\d+)?$')]
    [string] $TargetVersion,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string] $RepoRootPath = (Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')).Path,

    [Parameter()]
    [switch] $IncludeAllPsd1,

    [Parameter()]
    [switch] $CreateBackup
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-ManifestPaths {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $RepoRootPath,

        [Parameter()]
        [switch] $IncludeAllPsd1
    )

    $srcRoot = Join-Path -Path $RepoRootPath -ChildPath 'src'
    if (-not (Test-Path -Path $srcRoot)) {
        throw "Source folder not found: $srcRoot"
    }

    $all = Get-ChildItem -Path $srcRoot -Recurse -Filter '*.psd1' -File |
        Where-Object { $_.FullName -notmatch '[\\/]obj[\\/]|[\\/]bin[\\/]' }

    if ($IncludeAllPsd1) {
        return $all.FullName
    }

    # Default behavior:
    # Only treat ./src/<ModuleName>/<ModuleName>.psd1 as a shipped module manifest.
    $filtered = foreach ($file in $all) {
        $dir = Split-Path -Path $file.FullName -Parent
        $moduleName = Split-Path -Path $dir -Leaf
        $expectedName = "$moduleName.psd1"

        if ((Split-Path -Path $file.FullName -Leaf) -ieq $expectedName) {
            $file.FullName
        }
    }

    return $filtered
}

function Get-ManifestModuleInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ManifestPath
    )

    $content = Get-Content -Path $ManifestPath -Raw

    $moduleVersion =
        if ($content -match "(?m)^\s*ModuleVersion\s*=\s*'([^']+)'") { $Matches[1] }
        else { $null }

    $moduleName = Split-Path -Path (Split-Path -Path $ManifestPath -Parent) -Leaf

    [pscustomobject]@{
        ModuleName    = $moduleName
        ModuleVersion = $moduleVersion
        ManifestPath  = $ManifestPath
    }
}

function Set-ManifestModuleVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ManifestPath,

        [Parameter(Mandatory)]
        [string] $TargetVersion,

        [Parameter()]
        [switch] $CreateBackup
    )

    $content = Get-Content -Path $ManifestPath -Raw

    if ($content -notmatch '(?m)^\s*ModuleVersion\s*=') {
        Write-Warning "Skipping (no ModuleVersion found): $ManifestPath"
        return $false
    }

    # Replace only the ModuleVersion assignment line.
    # Keep formatting stable and avoid broad PSD1 rewrites.
    $newContent = [regex]::Replace(
        $content,
        "(?m)^\s*ModuleVersion\s*=\s*'[^']+'",
        "    ModuleVersion = '$TargetVersion'"
    )

    if ($newContent -eq $content) {
        # Already at desired version (or line format was unexpected but matched to same text).
        return $false
    }

    if ($CreateBackup) {
        $backupPath = "$ManifestPath.bak"
        Copy-Item -Path $ManifestPath -Destination $backupPath -Force
    }

    # Preserve file as text and avoid adding an extra trailing newline beyond original.
    Set-Content -Path $ManifestPath -Value $newContent -NoNewline

    return $true
}

$manifestPaths = Get-ManifestPaths -RepoRootPath $RepoRootPath -IncludeAllPsd1:$IncludeAllPsd1
if (-not $manifestPaths -or $manifestPaths.Count -eq 0) {
    throw "No module manifests found under: $(Join-Path -Path $RepoRootPath -ChildPath 'src')"
}

Write-Host "TargetVersion: $TargetVersion"
Write-Host "RepoRootPath : $RepoRootPath"
Write-Host "Manifests    : $($manifestPaths.Count)"
Write-Host ""

$changed = 0
foreach ($path in $manifestPaths) {
    $action = "Set ModuleVersion to '$TargetVersion' in $path"
    if ($PSCmdlet.ShouldProcess($path, $action)) {
        $didChange = Set-ManifestModuleVersion -ManifestPath $path -TargetVersion $TargetVersion -CreateBackup:$CreateBackup
        if ($didChange) {
            $changed++
            Write-Host "Updated: $path"
        }
        else {
            Write-Host "No change: $path"
        }
    }
}

Write-Host ""
Write-Host "Done. Updated manifests: $changed / $($manifestPaths.Count)"
Write-Host ""

$summary = foreach ($path in $manifestPaths) {
    Get-ManifestModuleInfo -ManifestPath $path
}

$summary |
    Sort-Object ModuleName |
    Format-Table -AutoSize ModuleName, ModuleVersion, ManifestPath

# Sanity checks
$missingVersion = $summary | Where-Object { -not $_.ModuleVersion }
if ($missingVersion) {
    $list = ($missingVersion | Select-Object -ExpandProperty ManifestPath) -join [Environment]::NewLine
    throw "Sanity check failed. One or more manifests do not contain 'ModuleVersion':`n$list"
}

$wrongVersion = $summary | Where-Object { $_.ModuleVersion -ne $TargetVersion }
if ($wrongVersion) {
    $list = ($wrongVersion | ForEach-Object { "$($_.ManifestPath) -> $($_.ModuleVersion)" }) -join [Environment]::NewLine
    throw "Sanity check failed. One or more manifests are not set to target version '$TargetVersion':`n$list"
}

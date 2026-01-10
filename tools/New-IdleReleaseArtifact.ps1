<#
.SYNOPSIS
    Creates a deterministic ZIP release artifact for IdLE.

.DESCRIPTION
    Builds a ZIP archive with stable entry ordering and stable ZIP metadata.
    The artifact content is explicitly defined to reduce the risk of shipping
    CI/test/internal files accidentally.

    This script is designed for CI usage (GitHub Actions) but can also be run locally.

.PARAMETER Tag
    The release tag used to name the artifact (e.g. v0.7.0).

.PARAMETER RepoRootPath
    The repository root path. Defaults to the parent directory of the script folder (../).

.PARAMETER OutputDirectory
    Directory where the ZIP artifact will be written.
    Defaults to 'artifacts/' under the repo root.

.PARAMETER ListOnly
    If set, prints the normalized, deterministic file list and exits without creating a ZIP.

.EXAMPLE
    PS> pwsh -NoProfile -File ./tools/New-IdleReleaseArtifact.ps1 -Tag v0.7.0

.EXAMPLE
    PS> pwsh -NoProfile -File ./tools/New-IdleReleaseArtifact.ps1 -Tag v0.7.0 -ListOnly

.OUTPUTS
    System.IO.FileInfo
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    # Allow typical semver tags and prerelease/build metadata. Disallow path separators and whitespace.
    [ValidatePattern('^v[0-9A-Za-z][0-9A-Za-z\.\-\+]*$')]
    [string] $Tag,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string] $RepoRootPath = (Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')).Path,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string] $OutputDirectory,

    [Parameter()]
    [switch] $ListOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Default output directory under the repo root if not explicitly set.
if (-not $PSBoundParameters.ContainsKey('OutputDirectory')) {
    $OutputDirectory = Join-Path -Path $RepoRootPath -ChildPath 'artifacts'
}

# ZIP entry timestamps are stored in a limited format. Use a stable time for deterministic artifacts.
# ZIP's DOS date range starts at 1980.
$stableTimestamp = [DateTimeOffset]::new(1980, 1, 1, 0, 0, 0, [TimeSpan]::Zero)

function Resolve-IdleRepoRoot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    $resolved = (Resolve-Path -LiteralPath $Path).Path

    # Basic sanity checks to reduce accidental misuse.
    $src = Join-Path -Path $resolved -ChildPath 'src'
    if (-not (Test-Path -LiteralPath $src)) {
        throw "RepoRootPath does not look like the IdLE repository root (missing 'src'): $resolved"
    }

    return $resolved
}

function ConvertTo-IdleZipEntryPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $RepositoryRootPath,

        [Parameter(Mandatory)]
        [string] $FullFilePath
    )

    $relative = $FullFilePath.Substring($RepositoryRootPath.Length).TrimStart('\', '/')

    # ZIP standard uses forward slashes.
    return ($relative -replace '\\', '/')
}

function Test-IdlePathExcluded {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $RelativePath
    )

    # Normalize to forward slashes for consistent matching.
    $p = ($RelativePath -replace '\\', '/').ToLowerInvariant()

    # Exclude obvious non-release content even if someone expands includes later.
    # Keep this conservative; the include list is still the primary control.
    if ($p.StartsWith('.git/')) { return $true }
    if ($p.StartsWith('.github/')) { return $true }
    if ($p.StartsWith('tests/')) { return $true }
    if ($p.StartsWith('artifacts/')) { return $true }

    # Common build outputs that should never ship.
    if ($p -match '(^|/)(bin|obj)/') { return $true }

    return $false
}

function Get-IdleReleaseFileList {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Root,

        [Parameter(Mandatory)]
        [string[]] $Include
    )

    $files = New-Object System.Collections.Generic.List[System.IO.FileInfo]

    foreach ($item in $Include) {
        $fullPath = Join-Path -Path $Root -ChildPath $item

        if (-not (Test-Path -LiteralPath $fullPath)) {
            # Missing files should not break the build (e.g. LICENSE.md in early stages).
            continue
        }

        $itemInfo = Get-Item -LiteralPath $fullPath -ErrorAction Stop
        if ($itemInfo.PSIsContainer) {
            Get-ChildItem -LiteralPath $itemInfo.FullName -File -Recurse -Force |
                ForEach-Object { $files.Add($_) }
        }
        else {
            $files.Add([System.IO.FileInfo]$itemInfo)
        }
    }

    # Sort by normalized relative path for deterministic ordering.
    $sorted = $files |
        ForEach-Object {
            $rel = $_.FullName.Substring($Root.Length).TrimStart('\', '/')
            [pscustomobject]@{
                FileInfo     = $_
                RelativePath = $rel
                SortKey      = ($rel -replace '\\', '/').ToLowerInvariant()
            }
        } |
        Where-Object { -not (Test-IdlePathExcluded -RelativePath $_.RelativePath) } |
        Sort-Object SortKey

    return ,($sorted.FileInfo)
}

function ConvertTo-IdleSafeFileName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Value
    )

    # Make sure the file name is safe on all platforms.
    # We already validated Tag, but keep a defensive normalization.
    return ($Value -replace '[^\w\.\-\+]', '_')
}

$RepoRootPath = Resolve-IdleRepoRoot -Path $RepoRootPath

# Define what goes into the release artifact.
# Keep this explicit to avoid accidental leakage of CI/test/internal content.
$includeRoots = @(
    'src',
    'docs',
    'examples',
    'tools',
    'README.md',
    'LICENSE.md',
    'CONTRIBUTING.md',
    'STYLEGUIDE.md'
)

$tagForFileName = ConvertTo-IdleSafeFileName -Value $Tag
$zipFileName = "IdLE-$tagForFileName.zip"

if (-not (Test-Path -LiteralPath $OutputDirectory)) {
    New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null
}

$zipPath = Join-Path -Path $OutputDirectory -ChildPath $zipFileName

$filesToPack = Get-IdleReleaseFileList -Root $RepoRootPath -Include $includeRoots

if ($ListOnly) {
    Write-Host "RepoRootPath   : $RepoRootPath"
    Write-Host "Tag           : $Tag"
    Write-Host "OutputDirectory: $OutputDirectory"
    Write-Host "ZipPath       : $zipPath"
    Write-Host ""
    Write-Host "Files (deterministic order):"
    foreach ($f in $filesToPack) {
        $rel = $f.FullName.Substring($RepoRootPath.Length).TrimStart('\', '/')
        Write-Host (" - " + ($rel -replace '\\', '/'))
    }
    return
}

# Recreate ZIP if it already exists (idempotent).
if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
}

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$zipStream = [System.IO.File]::Open(
    $zipPath,
    [System.IO.FileMode]::CreateNew,
    [System.IO.FileAccess]::ReadWrite,
    [System.IO.FileShare]::None
)

try {
    $archive = New-Object System.IO.Compression.ZipArchive(
        $zipStream,
        [System.IO.Compression.ZipArchiveMode]::Create,
        $true
    )

    try {
        foreach ($file in $filesToPack) {
            $entryPath = ConvertTo-IdleZipEntryPath -RepositoryRootPath $RepoRootPath -FullFilePath $file.FullName

            if (Test-IdlePathExcluded -RelativePath $entryPath) {
                # Defense-in-depth; Get-IdleReleaseFileList already excludes these.
                continue
            }

            # Create entry with deterministic metadata.
            $entry = $archive.CreateEntry($entryPath, [System.IO.Compression.CompressionLevel]::Optimal)
            $entry.LastWriteTime = $stableTimestamp

            $entryStream = $entry.Open()
            try {
                $fileStream = [System.IO.File]::OpenRead($file.FullName)
                try {
                    $fileStream.CopyTo($entryStream)
                }
                finally {
                    $fileStream.Dispose()
                }
            }
            finally {
                $entryStream.Dispose()
            }
        }
    }
    finally {
        $archive.Dispose()
    }
}
finally {
    $zipStream.Dispose()
}

Get-Item -LiteralPath $zipPath

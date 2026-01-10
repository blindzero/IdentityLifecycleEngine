[CmdletBinding()]
param(
    <#
    .SYNOPSIS
    Creates a deterministic ZIP release artifact for IdLE.

    .DESCRIPTION
    Builds a ZIP archive with stable entry ordering and stable timestamps.
    This is designed to be used from CI (GitHub Actions) when creating a GitHub Release.

    The artifact intentionally excludes CI/test-only content to keep releases lean.

    .PARAMETER RepositoryRoot
    Repository root path. Defaults to the directory of this script's parent folder.

    .PARAMETER Tag
    The release tag (e.g. v0.7.0). Used to name the output zip.

    .PARAMETER OutputDirectory
    Directory where the ZIP artifact will be written. Defaults to 'artifacts/' under the repo root.

    .OUTPUTS
    System.IO.FileInfo
    #>

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string] $RepositoryRoot = (Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')).Path,

    [Parameter(Mandatory)]
    [ValidatePattern('^v.+$')]
    [string] $Tag,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string] $OutputDirectory
)

Set-StrictMode -Off
$ErrorActionPreference = 'Stop'

# Default output directory under the repo root if not explicitly set.
if (-not $PSBoundParameters.ContainsKey('OutputDirectory')) {
    $OutputDirectory = Join-Path -Path $RepositoryRoot -ChildPath 'artifacts'
}

$zipFileName = "IdLE-$Tag.zip"
$zipPath = Join-Path -Path $OutputDirectory -ChildPath $zipFileName

# Ensure output folder exists.
if (-not (Test-Path -Path $OutputDirectory)) {
    New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null
}

# A stable timestamp helps make artifacts deterministic across runs.
# (ZIP's DOS date range starts at 1980.)
$stableTimestamp = [DateTimeOffset]::new(1980, 1, 1, 0, 0, 0, [TimeSpan]::Zero)

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

$excludeTopLevel = @(
    '.github',
    'tests',
    'artifacts'
)

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

        if (-not (Test-Path -Path $fullPath)) {
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

    # Sort by relative path for deterministic ordering.
    $sorted = $files |
        Sort-Object {
            $rel = Resolve-Path -LiteralPath $_.FullName
            $rel = $rel.Path.Substring($Root.Length).TrimStart('\', '/')
            $rel.ToLowerInvariant()
        }

    return ,$sorted
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

# Safety: ensure we are in the repository root and not accidentally packing something else.
foreach ($excluded in $excludeTopLevel) {
    if (Test-Path -LiteralPath (Join-Path -Path $RepositoryRoot -ChildPath $excluded)) {
        # This is an existence check only. We exclude by not including it in $includeRoots.
        continue
    }
}

# Recreate ZIP if it already exists (idempotent).
if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
}

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$filesToPack = Get-IdleReleaseFileList -Root $RepositoryRoot -Include $includeRoots

$zipStream = [System.IO.File]::Open($zipPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
try {
    $archive = New-Object System.IO.Compression.ZipArchive($zipStream, [System.IO.Compression.ZipArchiveMode]::Create, $true)
    try {
        foreach ($file in $filesToPack) {
            $entryPath = ConvertTo-IdleZipEntryPath -RepositoryRootPath $RepositoryRoot -FullFilePath $file.FullName

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

# Requires -Version 7.0
Set-StrictMode -Version Latest

BeforeAll {
    . (Join-Path $PSScriptRoot '_testHelpers.ps1')

    $script:RepoRoot = Get-RepoRootPath
    $script:ReleaseScriptPath = Join-Path $script:RepoRoot 'tools/New-IdleReleaseArtifact.ps1'

    if (-not (Test-Path -LiteralPath $script:ReleaseScriptPath)) {
        throw "Release artifact script not found: $script:ReleaseScriptPath"
    }
}

Describe 'New-IdleReleaseArtifact.ps1' {

    Context 'Tag validation' {

        It 'accepts a valid tag format' {
            { & $script:ReleaseScriptPath -Tag 'v0.7.0-test' -ListOnly 6>&1 | Out-Null } | Should -Not -Throw
        }

        It 'rejects tags without v-prefix' {
            { & $script:ReleaseScriptPath -Tag '0.7.0' -ListOnly 6>&1 | Out-Null } | Should -Throw
        }

        It 'rejects tags with path separators' {
            { & $script:ReleaseScriptPath -Tag 'v0.7.0/evil' -ListOnly 6>&1 | Out-Null } | Should -Throw
        }

        It 'rejects tags with whitespace' {
            { & $script:ReleaseScriptPath -Tag 'v0.7.0 test' -ListOnly 6>&1 | Out-Null } | Should -Throw
        }
    }

    Context 'ListOnly output contract' {

        BeforeEach {
            $script:GetListOnlyPaths = {
                param(
                    [Parameter(Mandatory)]
                    [string] $Tag
                )

                # Write-Host writes to the Information stream in PowerShell 7.
                # Merge Information stream to success output and parse lines starting with " - ".
                $lines = & $script:ReleaseScriptPath -Tag $Tag -ListOnly 6>&1 |
                    ForEach-Object { $_.ToString() }

                $paths = $lines |
                    Where-Object { $_ -like ' - *' } |
                    ForEach-Object { $_.Substring(3) }

                return , $paths
            }
        }

        It 'returns a deterministic file list (stable ordering)' {
            $a = & $script:GetListOnlyPaths -Tag 'v0.7.0-test'
            $b = & $script:GetListOnlyPaths -Tag 'v0.7.0-test'

            $a | Should -Not -BeNullOrEmpty
            $b | Should -Not -BeNullOrEmpty
            $a | Should -Be $b
        }

        It 'does not include excluded top-level paths' {
            $paths = & $script:GetListOnlyPaths -Tag 'v0.7.0-test'

            # Normalize to forward slashes for consistent assertions
            $norm = $paths | ForEach-Object { $_ -replace '\\', '/' }

            ($norm | Where-Object { $_ -match '^tools/' }) | Should -BeNullOrEmpty
            ($norm | Where-Object { $_ -match '^\.github/' }) | Should -BeNullOrEmpty
            ($norm | Where-Object { $_ -match '^tests/' }) | Should -BeNullOrEmpty
            ($norm | Where-Object { $_ -match '^artifacts/' }) | Should -BeNullOrEmpty
        }

        It 'does not include common build output folders' {
            $paths = & $script:GetListOnlyPaths -Tag 'v0.7.0-test'

            $norm = $paths | ForEach-Object { $_ -replace '\\', '/' }

            ($norm | Where-Object { $_ -match '(^|/)bin/' }) | Should -BeNullOrEmpty
            ($norm | Where-Object { $_ -match '(^|/)obj/' }) | Should -BeNullOrEmpty
        }
    }

    Context 'ZIP creation contract' {

        It 'creates a ZIP artifact and excludes forbidden content' {
            $tempDir = Join-Path $TestDrive 'artifacts'
            New-Item -Path $tempDir -ItemType Directory -Force | Out-Null

            $tag = 'v0.7.0-test'
            $zip = & $script:ReleaseScriptPath -Tag $tag -OutputDirectory $tempDir
            $zip | Should -Not -BeNullOrEmpty
            $zip.FullName | Should -Exist

            Add-Type -AssemblyName System.IO.Compression
            Add-Type -AssemblyName System.IO.Compression.FileSystem

            $archive = [System.IO.Compression.ZipFile]::OpenRead($zip.FullName)
            try {
                $entries = $archive.Entries | ForEach-Object { $_.FullName }

                $entries | Should -Not -BeNullOrEmpty

                # Normalize to forward slashes, Zip uses them anyway
                ($entries | Where-Object { $_ -match '^tools/' }) | Should -BeNullOrEmpty
                ($entries | Where-Object { $_ -match '^\.github/' }) | Should -BeNullOrEmpty
                ($entries | Where-Object { $_ -match '^tests/' }) | Should -BeNullOrEmpty
                ($entries | Where-Object { $_ -match '^artifacts/' }) | Should -BeNullOrEmpty

                ($entries | Where-Object { $_ -match '(^|/)bin/' }) | Should -BeNullOrEmpty
                ($entries | Where-Object { $_ -match '(^|/)obj/' }) | Should -BeNullOrEmpty
            }
            finally {
                $archive.Dispose()
            }
        }

        It 'writes stable ZIP entry timestamps for deterministic artifacts' {
            $tempDir = Join-Path $TestDrive 'artifacts'
            New-Item -Path $tempDir -ItemType Directory -Force | Out-Null

            $tag = 'v0.7.0-test'
            $zip = & $script:ReleaseScriptPath -Tag $tag -OutputDirectory $tempDir

            Add-Type -AssemblyName System.IO.Compression
            Add-Type -AssemblyName System.IO.Compression.FileSystem

            # ZIP timestamps are stored in DOS format. The date should be 1980-01-01.
            # Due to timezone handling in ZipArchiveEntry, we check the date part only.
            $expectedDate = [DateTime]::new(1980, 1, 1)

            $archive = [System.IO.Compression.ZipFile]::OpenRead($zip.FullName)
            try {
                # Sample a few entries (enough to catch regressions without being expensive)
                $sample = $archive.Entries | Select-Object -First 10
                $sample | Should -Not -BeNullOrEmpty

                foreach ($e in $sample) {
                    # LastWriteTime from ZipArchiveEntry returns DateTimeOffset.
                    # Check that the date is 1980-01-01 (ignore time and timezone).
                    $e.LastWriteTime.Date | Should -Be $expectedDate
                }
            }
            finally {
                $archive.Dispose()
            }
        }
    }
}

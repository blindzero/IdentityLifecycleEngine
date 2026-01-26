Set-StrictMode -Version Latest

# Dot-source domain-specific test helpers
. (Join-Path -Path $PSScriptRoot -ChildPath 'Steps/_testHelpers.Steps.ps1')
. (Join-Path -Path $PSScriptRoot -ChildPath 'Providers/_testHelpers.Providers.ps1')

function Get-RepoRootPath {
    [CmdletBinding()]
    param()

    # tests/ is expected to be located in repo root.
    return (Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')).Path
}

function Get-IdleModuleManifestPath {
    [CmdletBinding()]
    param()

    $repoRoot = Get-RepoRootPath
    return (Resolve-Path -Path (Join-Path $repoRoot 'src/IdLE/IdLE.psd1')).Path
}

function Import-IdleTestModule {
    [CmdletBinding()]
    param()

    $manifestPath = Get-IdleModuleManifestPath
    Import-Module -Name $manifestPath -Force -ErrorAction Stop

    $stepsCommonManifestPath = Resolve-Path -Path (Join-Path (Get-RepoRootPath) 'src/IdLE.Steps.Common/IdLE.Steps.Common.psd1')
    Import-Module -Name $stepsCommonManifestPath -Force -ErrorAction Stop

    $stepsDirectorySyncManifestPath = Resolve-Path -Path (Join-Path (Get-RepoRootPath) 'src/IdLE.Steps.DirectorySync/IdLE.Steps.DirectorySync.psd1')
    Import-Module -Name $stepsDirectorySyncManifestPath -Force -ErrorAction Stop

    $mockProviderManifestPath = Resolve-Path -Path (Join-Path (Get-RepoRootPath) 'src/IdLE.Provider.Mock/IdLE.Provider.Mock.psd1')
    Import-Module -Name $mockProviderManifestPath -Force -ErrorAction Stop

    $directorySyncProviderManifestPath = Resolve-Path -Path (Join-Path (Get-RepoRootPath) 'src/IdLE.Provider.DirectorySync.EntraConnect/IdLE.Provider.DirectorySync.EntraConnect.psd1')
    Import-Module -Name $directorySyncProviderManifestPath -Force -ErrorAction Stop

    $stepsMailboxManifestPath = Resolve-Path -Path (Join-Path (Get-RepoRootPath) 'src/IdLE.Steps.Mailbox/IdLE.Steps.Mailbox.psd1')
    Import-Module -Name $stepsMailboxManifestPath -Force -ErrorAction Stop
}

function Get-ModuleManifestPaths {
    [CmdletBinding()]
    param()

    $repoRoot = Get-RepoRootPath
    $srcRoot = Join-Path -Path $repoRoot -ChildPath 'src'

    # module manifests only (one level deep)
    return Get-ChildItem -Path $srcRoot -Filter '*.psd1' -File -Recurse |
        Where-Object { $_.FullName -match [regex]::Escape([IO.Path]::Combine('src', '')) } |
        Where-Object { $_.Directory.Parent -and $_.Directory.Parent.Name -eq 'src' } |
        Select-Object -ExpandProperty FullName
}


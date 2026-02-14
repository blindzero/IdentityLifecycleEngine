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
}

function Import-IdleTestMailboxModule {
    <#
    .SYNOPSIS
    Imports the IdLE.Steps.Mailbox module for tests that specifically need it.
    
    .DESCRIPTION
    This is a separate function to avoid polluting all test sessions with the Mailbox module.
    Only tests that specifically work with mailbox steps should call this.
    #>
    [CmdletBinding()]
    param()

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

function New-IdleTestRequest {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string] $LifecycleEvent = 'Joiner',

        [Parameter()]
        [hashtable] $IdentityKeys,

        [Parameter()]
        [hashtable] $DesiredState,

        [Parameter()]
        [hashtable] $Changes,

        [Parameter()]
        [string] $CorrelationId,

        [Parameter()]
        [string] $Actor
    )

    $params = @{ LifecycleEvent = $LifecycleEvent }

    if ($PSBoundParameters.ContainsKey('IdentityKeys')) { $params.IdentityKeys = $IdentityKeys }
    if ($PSBoundParameters.ContainsKey('DesiredState')) { $params.DesiredState = $DesiredState }
    if ($PSBoundParameters.ContainsKey('Changes')) { $params.Changes = $Changes }
    if ($PSBoundParameters.ContainsKey('CorrelationId')) { $params.CorrelationId = $CorrelationId }
    if ($PSBoundParameters.ContainsKey('Actor')) { $params.Actor = $Actor }

    return New-IdleRequest @params
}

function New-IdleTestWorkflowFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Content,

        [Parameter()]
        [string] $FileName = 'test.psd1',

        [Parameter()]
        [string] $BasePath
    )

    if (-not $BasePath) {
        $testDriveVar = $null
        foreach ($scope in @('Local', 'Script', 'Global', 1, 2)) {
            try {
                $testDriveVar = Get-Variable -Name TestDrive -Scope $scope -ErrorAction SilentlyContinue
                if ($testDriveVar) { break }
            } catch {
                continue
            }
        }

        if ($testDriveVar) {
            $BasePath = $testDriveVar.Value
        } else {
            throw 'BasePath is required when TestDrive is not available.'
        }
    }

    $path = Join-Path -Path $BasePath -ChildPath $FileName
    Set-Content -Path $path -Encoding UTF8 -Value $Content
    return $path
}

function New-IdleTestModuleLayout {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $DestinationRoot,

        [Parameter()]
        [string[]] $Modules = @('IdLE', 'IdLE.Core', 'IdLE.Steps.Common')
    )

    $repoRoot = Get-RepoRootPath

    if (-not (Test-Path -Path $DestinationRoot)) {
        $null = New-Item -Path $DestinationRoot -ItemType Directory -Force
    }

    foreach ($moduleName in $Modules) {
        $sourcePath = Join-Path -Path $repoRoot -ChildPath (Join-Path 'src' $moduleName)
        $destPath = Join-Path -Path $DestinationRoot -ChildPath $moduleName
        Copy-Item -Path $sourcePath -Destination $destPath -Recurse -Force
    }

    return [pscustomobject]@{
        Root    = $DestinationRoot
        Modules = $Modules
    }
}

function Invoke-IdleIsolatedPwsh {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Script,

        [Parameter()]
        [hashtable] $Environment,

        [Parameter()]
        [string] $WorkingDirectory
    )

    $pwshPath = (Get-Command -Name 'pwsh' -ErrorAction Stop).Source
    $encoded = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($Script))

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $pwshPath
    $psi.Arguments = "-NoProfile -NonInteractive -EncodedCommand $encoded"
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false

    if ($WorkingDirectory) {
        $psi.WorkingDirectory = $WorkingDirectory
    }

    if ($Environment) {
        foreach ($key in $Environment.Keys) {
            $value = $Environment[$key]
            $psi.Environment[$key] = if ($null -eq $value) { '' } else { [string]$value }
        }
    }

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $psi
    $null = $process.Start()

    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()

    return [pscustomobject]@{
        ExitCode = $process.ExitCode
        StdOut   = $stdout
        StdErr   = $stderr
    }
}


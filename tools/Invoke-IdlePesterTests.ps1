<#
.SYNOPSIS
Runs IdLE Pester tests and optionally emits CI artifacts (test results + coverage).

.DESCRIPTION
This script is the canonical entry point for running Pester in the IdLE repository.

It is designed to be:
- deterministic (fixed artifact paths under repo root)
- CI-friendly (NUnitXml results + coverage output on demand)
- robust against different working directories (resolves paths relative to repo root)

The script ensures Pester is available and imports it before running tests.

.PARAMETER TestPath
Path to the tests folder. Defaults to 'tests' relative to the repository root.

.PARAMETER CI
Enables CI mode:
- Writes NUnitXml test results to -TestResultsPath
- Enables code coverage and writes a coverage report to -CoverageOutputPath

.PARAMETER TestResultsPath
Path to the NUnitXml test results file. Defaults to 'artifacts/test-results.xml'
relative to the repository root.

.PARAMETER EnableCoverage
Enables code coverage when not running in -CI mode.

.PARAMETER CoverageOutputPath
Path to the coverage report file. Defaults to 'artifacts/coverage.xml'
relative to the repository root.

.PARAMETER CoverageOutputFormat
Coverage output format supported by Pester.

.PARAMETER CoveragePath
One or more paths to include for coverage (e.g. 'src'). Defaults to 'src'
relative to the repository root.

.PARAMETER PesterVersion
Pinned Pester version to use. Defaults to 5.7.1.

.EXAMPLE
pwsh -NoProfile -File ./tools/Invoke-IdlePesterTests.ps1

.EXAMPLE
pwsh -NoProfile -File ./tools/Invoke-IdlePesterTests.ps1 -CI

.EXAMPLE
pwsh -NoProfile -File ./tools/Invoke-IdlePesterTests.ps1 -EnableCoverage -CoverageOutputFormat Cobertura

.OUTPUTS
None. Throws on failures and uses Pester exit codes when configured.
#>

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string] $TestPath = 'tests',

    [Parameter()]
    [switch] $CI,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string] $TestResultsPath = 'artifacts/test-results.xml',

    [Parameter()]
    [switch] $EnableCoverage,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string] $CoverageOutputPath = 'artifacts/coverage.xml',

    [Parameter()]
    [ValidateSet('JaCoCo', 'Cobertura', 'CoverageGutters')]
    [string] $CoverageOutputFormat = 'JaCoCo',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string[]] $CoveragePath = @('src'),

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [version] $PesterVersion = '5.7.1'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-IdleRepoRoot {
    <#
    .SYNOPSIS
    Resolves the repository root path.

    .DESCRIPTION
    The repo root is assumed to be the parent directory of the 'tools' folder.
    This avoids relying on the current working directory.
    #>
    [CmdletBinding()]
    param()

    return (Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')).Path
}

function Get-IdleFullPath {
    <#
    .SYNOPSIS
    Returns a full path for a repository-relative or absolute path.

    .DESCRIPTION
    Resolve-Path fails if the path does not exist (e.g. output files).
    This helper returns a normalized full path regardless of existence.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $RepoRootPath,

        [Parameter(Mandatory)]
        [string] $Path
    )

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }

    return [System.IO.Path]::GetFullPath((Join-Path -Path $RepoRootPath -ChildPath $Path))
}

function Ensure-Directory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -ItemType Directory -Force | Out-Null
    }
}

function Ensure-Pester {
    <#
    .SYNOPSIS
    Ensures Pester is installed (pinned version) and imported.

    .DESCRIPTION
    CI runners are ephemeral. When missing, we install Pester in CurrentUser scope.
    We explicitly pin versions for determinism.

    IMPORTANT:
    - We keep this logic self-contained and consistent across local + CI runs.
    - We avoid auto-upgrading to newer versions unless the pinned version is changed in code.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [version] $RequiredVersion
    )

    $installed = Get-Module -ListAvailable -Name Pester |
        Where-Object { $_.Version -eq $RequiredVersion } |
        Select-Object -First 1

    if (-not $installed) {
        if (-not (Get-Command -Name Install-Module -ErrorAction SilentlyContinue)) {
            throw "Pester ($RequiredVersion) is required, but Install-Module is not available. Install Pester manually and retry."
        }

        Write-Host "Installing Pester ($RequiredVersion) in CurrentUser scope..."
        Install-Module -Name Pester -Scope CurrentUser -Force -RequiredVersion $RequiredVersion -AllowClobber | Out-Null
    }

    Import-Module -Name Pester -RequiredVersion $RequiredVersion -Force
}

$repoRoot = Resolve-IdleRepoRoot

$resolvedTestPath = Get-IdleFullPath -RepoRootPath $repoRoot -Path $TestPath
if (-not (Test-Path -LiteralPath $resolvedTestPath)) {
    throw "TestPath does not exist: $resolvedTestPath"
}

$emitTestResults = $CI.IsPresent
$coverageEnabled = $CI.IsPresent -or $EnableCoverage.IsPresent

$resolvedTestResultsPath = $null
if ($emitTestResults) {
    $resolvedTestResultsPath = Get-IdleFullPath -RepoRootPath $repoRoot -Path $TestResultsPath
    Ensure-Directory -Path (Split-Path -Path $resolvedTestResultsPath -Parent)
}

$resolvedCoverageOutputPath = $null
$resolvedCoveragePaths = @()

if ($coverageEnabled) {
    $resolvedCoverageOutputPath = Get-IdleFullPath -RepoRootPath $repoRoot -Path $CoverageOutputPath
    Ensure-Directory -Path (Split-Path -Path $resolvedCoverageOutputPath -Parent)

    foreach ($p in $CoveragePath) {
        $resolvedCoveragePaths += (Get-IdleFullPath -RepoRootPath $repoRoot -Path $p)
    }
}

Ensure-Pester -RequiredVersion $PesterVersion

$config = New-PesterConfiguration
$config.Run.Path = $resolvedTestPath
$config.Run.Exit = $true
$config.Output.Verbosity = 'Detailed'

if ($emitTestResults -and $resolvedTestResultsPath) {
    $config.TestResult.Enabled = $true
    $config.TestResult.OutputFormat = 'NUnitXml'
    $config.TestResult.OutputPath = $resolvedTestResultsPath
}

if ($coverageEnabled -and $resolvedCoverageOutputPath) {
    if (-not $config.PSObject.Properties.Name.Contains('CodeCoverage')) {
        throw "Installed Pester does not expose CodeCoverage configuration. Install a newer Pester version and retry."
    }

    $config.CodeCoverage.Enabled = $true
    $config.CodeCoverage.Path = $resolvedCoveragePaths

    if ($config.CodeCoverage.PSObject.Properties.Name.Contains('OutputPath')) {
        $config.CodeCoverage.OutputPath = $resolvedCoverageOutputPath
    }
    else {
        throw "Installed Pester does not support CodeCoverage.OutputPath. Install a newer Pester version and retry."
    }

    if ($config.CodeCoverage.PSObject.Properties.Name.Contains('OutputFormat')) {
        $config.CodeCoverage.OutputFormat = $CoverageOutputFormat
    }
    elseif ($CI) {
        throw "Installed Pester does not support CodeCoverage.OutputFormat. Install a newer Pester version and retry."
    }
}

Invoke-Pester -Configuration $config

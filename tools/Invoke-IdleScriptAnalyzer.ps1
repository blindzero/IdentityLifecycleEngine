<#
.SYNOPSIS
Runs PSScriptAnalyzer for the IdLE repository with optional SARIF export.

.DESCRIPTION
This script is the canonical entry point for running PSScriptAnalyzer in the IdLE repository.

Design goals:
- Deterministic and CI-friendly defaults (repo-root settings, stable output paths)
- Optional SARIF output for GitHub Code Scanning integration
- No reliance on the current working directory
- Minimal dependencies with explicit version pinning

By default, the script analyzes 'src' and 'tools' using the repository-root
'PSScriptAnalyzerSettings.psd1'.

.PARAMETER Paths
One or more directories/files to analyze (relative to repo root by default).
Defaults to @('src', 'tools').

.PARAMETER SettingsPath
Path to the PSScriptAnalyzer settings file (relative to repo root by default).
Defaults to 'PSScriptAnalyzerSettings.psd1'.

.PARAMETER CI
Enables CI mode:
- Writes a JSON summary file to -JsonOutputPath (default under artifacts/)
- Writes SARIF when -SarifOutputPath is provided (default under artifacts/)
- Fails the run when findings meet -FailOnSeverity (default: Error)

.PARAMETER JsonOutputPath
Where to write a machine-readable JSON summary of findings
(relative to repo root by default). Defaults to 'artifacts/pssa-results.json'.

.PARAMETER SarifOutputPath
When provided, writes SARIF output to this path (relative to repo root by default).
Defaults to 'artifacts/pssa-results.sarif'.

.PARAMETER FailOnSeverity
Controls which findings should fail the run. Defaults to 'Error'.
Valid values: Error, Warning

.PARAMETER PSScriptAnalyzerVersion
Pinned PSScriptAnalyzer version to use. Defaults to 1.24.0.

.PARAMETER ConvertToSarifVersion
Pinned ConvertToSARIF module version to use (for SARIF export). Defaults to 1.0.0.

.EXAMPLE
pwsh -NoProfile -File ./tools/Invoke-IdleScriptAnalyzer.ps1

.EXAMPLE
pwsh -NoProfile -File ./tools/Invoke-IdleScriptAnalyzer.ps1 -CI

.EXAMPLE
pwsh -NoProfile -File ./tools/Invoke-IdleScriptAnalyzer.ps1 -CI -SarifOutputPath artifacts/pssa.sarif

.OUTPUTS
None. Writes optional output files and throws on failure.
#>

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string[]] $Paths = @('src', 'tools'),

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string] $SettingsPath = 'PSScriptAnalyzerSettings.psd1',

    [Parameter()]
    [switch] $CI,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string] $JsonOutputPath = 'artifacts/pssa-results.json',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string] $SarifOutputPath = 'artifacts/pssa-results.sarif',

    [Parameter()]
    [ValidateSet('Error', 'Warning')]
    [string] $FailOnSeverity = 'Error',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [version] $PSScriptAnalyzerVersion = '1.24.0',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [version] $ConvertToSarifVersion = '1.0.0'
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

function Ensure-Module {
    <#
    .SYNOPSIS
    Ensures a module is installed (pinned version) and imported.

    .DESCRIPTION
    CI runners are ephemeral. When missing, we install the module in CurrentUser scope.
    We explicitly pin versions for determinism.

    IMPORTANT:
    - We keep this logic self-contained and consistent across local + CI runs.
    - We avoid auto-upgrading to newer versions unless the pinned version is changed in code.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter(Mandatory)]
        [version] $RequiredVersion
    )

    $installed = Get-Module -ListAvailable -Name $Name |
        Where-Object { $_.Version -eq $RequiredVersion } |
        Select-Object -First 1

    if (-not $installed) {
        if (-not (Get-Command -Name Install-Module -ErrorAction SilentlyContinue)) {
            throw "Module '$Name' ($RequiredVersion) is required, but Install-Module is not available. Install the module manually and retry."
        }

        Write-Host "Installing module '$Name' ($RequiredVersion) in CurrentUser scope..."
        Install-Module -Name $Name -Scope CurrentUser -Force -RequiredVersion $RequiredVersion -AllowClobber | Out-Null
    }

    Import-Module -Name $Name -RequiredVersion $RequiredVersion -Force
}

function Write-JsonFile {
    <#
    .SYNOPSIS
    Writes a JSON file with deterministic encoding.

    .DESCRIPTION
    PowerShell defaults can differ across versions. We enforce UTF8 without BOM and
    ensure we always write a file (even when there are no findings).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [object] $Object
    )

    $json = $Object | ConvertTo-Json -Depth 10
    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $json, $encoding)
}

$repoRoot = Resolve-IdleRepoRoot

# Resolve and validate settings path.
$resolvedSettingsPath = Get-IdleFullPath -RepoRootPath $repoRoot -Path $SettingsPath
if (-not (Test-Path -LiteralPath $resolvedSettingsPath)) {
    throw "PSScriptAnalyzer settings file not found: $resolvedSettingsPath"
}

# Resolve analysis paths relative to repo root.
$resolvedPaths = @()
foreach ($p in $Paths) {
    $full = Get-IdleFullPath -RepoRootPath $repoRoot -Path $p
    if (-not (Test-Path -LiteralPath $full)) {
        throw "Analysis path not found: $full"
    }

    $resolvedPaths += $full
}

# Resolve output paths. We always write JSON in CI mode for artifact upload.
$resolvedJsonOutputPath = $null
if ($CI) {
    $resolvedJsonOutputPath = Get-IdleFullPath -RepoRootPath $repoRoot -Path $JsonOutputPath
    Ensure-Directory -Path (Split-Path -Path $resolvedJsonOutputPath -Parent)
}

# SARIF is optional: only generate when CI is on (or user explicitly wants it later)
# AND ConvertToSARIF is available.
$resolvedSarifOutputPath = $null
$emitSarif = $false
if ($CI -and $SarifOutputPath) {
    $resolvedSarifOutputPath = Get-IdleFullPath -RepoRootPath $repoRoot -Path $SarifOutputPath
    Ensure-Directory -Path (Split-Path -Path $resolvedSarifOutputPath -Parent)
    $emitSarif = $true
}

# Ensure analyzer module is present (pinned).
Ensure-Module -Name 'PSScriptAnalyzer' -RequiredVersion $PSScriptAnalyzerVersion

# Run analysis using the repo settings file.
# We rely on the settings file for rule selection and severities.
Write-Host "Running PSScriptAnalyzer ($PSScriptAnalyzerVersion) using settings: $resolvedSettingsPath"
Write-Host "Analyzing paths:"
$resolvedPaths | ForEach-Object { Write-Host "  - $_" }

$findings = Invoke-ScriptAnalyzer -Path $resolvedPaths -Recurse -Settings $resolvedSettingsPath

# Create a stable, small JSON payload (DiagnosticRecord contains complex members).
$summary = @(
    foreach ($f in ($findings | Sort-Object ScriptName, Line, Column, RuleName)) {
        [pscustomobject]@{
            RuleName   = $f.RuleName
            Severity   = $f.Severity
            Message    = $f.Message
            ScriptName = $f.ScriptName
            Line       = $f.Line
            Column     = $f.Column
        }
    }
)

if ($CI -and $resolvedJsonOutputPath) {
    Write-Host "Writing PSScriptAnalyzer JSON results: $resolvedJsonOutputPath"
    Write-JsonFile -Path $resolvedJsonOutputPath -Object $summary
}

if ($emitSarif -and $resolvedSarifOutputPath) {
    # ConvertToSARIF provides the ConvertTo-SARIF cmdlet which accepts -FilePath.
    # We install it only when SARIF output is requested.
    Ensure-Module -Name 'ConvertToSARIF' -RequiredVersion $ConvertToSarifVersion

    $convertCommand = Get-Command -Name 'ConvertTo-SARIF' -ErrorAction SilentlyContinue
    if (-not $convertCommand) {
        throw "ConvertToSARIF module is installed, but 'ConvertTo-SARIF' cmdlet was not found."
    }

    Write-Host "Writing SARIF results: $resolvedSarifOutputPath"
    $findings | & $convertCommand -FilePath $resolvedSarifOutputPath
}

# Determine whether we should fail this run.
$failSeverities = @($FailOnSeverity)
if ($FailOnSeverity -eq 'Warning') {
    # Warning implies: fail on both Warning and Error.
    $failSeverities = @('Warning', 'Error')
}

$blockingFindings = $findings | Where-Object { $failSeverities -contains $_.Severity }

if ($blockingFindings) {
    $errorCount = ($findings | Where-Object { $_.Severity -eq 'Error' }).Count
    $warningCount = ($findings | Where-Object { $_.Severity -eq 'Warning' }).Count

    $message = "PSScriptAnalyzer found blocking issues (FailOnSeverity: $FailOnSeverity). Errors: $errorCount, Warnings: $warningCount."
    throw $message
}

Write-Host "PSScriptAnalyzer completed with no blocking findings (FailOnSeverity: $FailOnSeverity)."

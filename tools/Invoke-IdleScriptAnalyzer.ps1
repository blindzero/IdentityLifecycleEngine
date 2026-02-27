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

function Initialize-Directory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -ItemType Directory -Force | Out-Null
    }
}

function Initialize-Module {
    <#
    .SYNOPSIS
    Initializes a module by ensuring it is installed (pinned version) and imported.

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

        Write-Host "  Installing module '$Name' ($RequiredVersion) in CurrentUser scope..." -ForegroundColor DarkGray
        Install-Module -Name $Name -Scope CurrentUser -Force -RequiredVersion $RequiredVersion -AllowClobber | Out-Null
    }

    Import-Module -Name $Name -RequiredVersion $RequiredVersion -Force
}

function Write-PssaFinding {
    <#
    .SYNOPSIS
    Writes a single PSScriptAnalyzer finding to the host with color coding.

    .DESCRIPTION
    Errors are written in red, warnings in yellow. Suppresses raw diagnostic
    object noise and formats the output for human readability.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Finding
    )

    $severity = [string]$Finding.Severity
    $color = if ($severity -eq 'Error') { 'Red' } else { 'Yellow' }
    $icon = if ($severity -eq 'Error') { [char]0x2717 } else { [char]0x26A0 }
    $label = if ($severity -eq 'Error') { 'Error  ' } else { 'Warning' }
    $scriptName = [System.IO.Path]::GetFileName([string]$Finding.ScriptPath)

    Write-Host "  $icon [$label]  $($Finding.RuleName)" -ForegroundColor $color
    Write-Host "           File : $scriptName  (line $($Finding.Line), col $($Finding.Column))" -ForegroundColor DarkGray
    Write-Host "           Msg  : $($Finding.Message)" -ForegroundColor DarkGray
    Write-Host ''
}

function Write-PssaHeader {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [version] $Version,

        [Parameter(Mandatory)]
        [string] $SettingsPath,

        [Parameter(Mandatory)]
        [string[]] $AnalyzedPaths
    )

    $separator = '-' * 64
    Write-Host $separator -ForegroundColor DarkCyan
    Write-Host "  PSScriptAnalyzer $Version" -ForegroundColor Cyan
    Write-Host "  Settings : $(Split-Path -Leaf $SettingsPath)" -ForegroundColor DarkCyan
    Write-Host '  Paths    :' -ForegroundColor DarkCyan
    foreach ($p in $AnalyzedPaths) {
        Write-Host "    > $p" -ForegroundColor DarkGray
    }
    Write-Host $separator -ForegroundColor DarkCyan
    Write-Host ''
}

function Write-PssaSummary {
    <#
    .SYNOPSIS
    Writes a color-coded summary of PSScriptAnalyzer results.

    .DESCRIPTION
    - Green : no findings at all
    - Yellow: only warnings present (local run passes, CI may flag if FailOnSeverity=Warning)
    - Red   : errors present (blocking findings)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]] $Findings,

        [Parameter(Mandatory)]
        [string] $FailOnSeverity
    )

    $errorCount = @($Findings | Where-Object { $_.Severity -eq 'Error' }).Count
    $warnCount = @($Findings | Where-Object { $_.Severity -eq 'Warning' }).Count
    $separator = '-' * 64

    Write-Host $separator -ForegroundColor DarkCyan

    if ($errorCount -eq 0 -and $warnCount -eq 0) {
        Write-Host "  $([char]0x2713) No findings — all checks passed." -ForegroundColor Green
    }
    else {
        Write-Host "  Findings : $($errorCount + $warnCount) total  |  $errorCount error(s)  |  $warnCount warning(s)" -ForegroundColor DarkGray

        if ($errorCount -gt 0) {
            Write-Host "  $([char]0x2717) $errorCount error(s) found — this run will FAIL." -ForegroundColor Red
        }

        if ($warnCount -gt 0 -and $FailOnSeverity -eq 'Error') {
            Write-Host "  $([char]0x26A0) $warnCount warning(s) found — these pass locally but CI will flag them if FailOnSeverity=Warning." -ForegroundColor Yellow
        }
        elseif ($warnCount -gt 0) {
            Write-Host "  $([char]0x26A0) $warnCount warning(s) found — this run will FAIL." -ForegroundColor Yellow
        }
    }

    Write-Host $separator -ForegroundColor DarkCyan
    Write-Host ''
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
    Initialize-Directory -Path (Split-Path -Path $resolvedJsonOutputPath -Parent)
}

# SARIF is optional: only generate when CI is on (or user explicitly wants it later)
# AND ConvertToSARIF is available.
$resolvedSarifOutputPath = $null
$emitSarif = $false
if ($CI -and $SarifOutputPath) {
    $resolvedSarifOutputPath = Get-IdleFullPath -RepoRootPath $repoRoot -Path $SarifOutputPath
    Initialize-Directory -Path (Split-Path -Path $resolvedSarifOutputPath -Parent)
    $emitSarif = $true
}

# Ensure analyzer module is present (pinned).
Initialize-Module -Name 'PSScriptAnalyzer' -RequiredVersion $PSScriptAnalyzerVersion

# Run analysis using the repo settings file.
# We rely on the settings file for rule selection and severities.
Write-PssaHeader -Version $PSScriptAnalyzerVersion -SettingsPath $resolvedSettingsPath -AnalyzedPaths $resolvedPaths

$findings = @()
foreach ($path in $resolvedPaths) {
    $findings += Invoke-ScriptAnalyzer -Path $path -Recurse -Settings $resolvedSettingsPath
}

# Display each finding with color coding (errors in red, warnings in yellow).
foreach ($f in ($findings | Sort-Object ScriptName, Line, Column, RuleName)) {
    Write-PssaFinding -Finding $f
}

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
    Write-Host "  Writing JSON results : $resolvedJsonOutputPath" -ForegroundColor DarkGray
    Write-JsonFile -Path $resolvedJsonOutputPath -Object $summary
}

if ($emitSarif -and $resolvedSarifOutputPath) {
    # ConvertToSARIF provides the ConvertTo-SARIF cmdlet which accepts -FilePath.
    # We install it only when SARIF output is requested.
    Initialize-Module -Name 'ConvertToSARIF' -RequiredVersion $ConvertToSarifVersion

    $convertCommand = Get-Command -Name 'ConvertTo-SARIF' -ErrorAction SilentlyContinue
    if (-not $convertCommand) {
        throw "ConvertToSARIF module is installed, but 'ConvertTo-SARIF' cmdlet was not found."
    }

    Write-Host "  Writing SARIF results : $resolvedSarifOutputPath" -ForegroundColor DarkGray
    $findings | & $convertCommand -FilePath $resolvedSarifOutputPath
}

# Display color-coded summary (green/yellow/red) with CI hint for warnings.
Write-PssaSummary -Findings $findings -FailOnSeverity $FailOnSeverity

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

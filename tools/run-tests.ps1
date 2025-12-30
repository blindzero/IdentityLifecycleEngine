[CmdletBinding()]
param(
    [Parameter()]
    [string] $TestPath = 'tests',

    [Parameter()]
    [switch] $CI,

    [Parameter()]
    [string] $TestResultsPath = 'artifacts/test-results.xml'
)

Set-StrictMode -Off
$ErrorActionPreference = 'Stop'

function Test-Pester {
    [CmdletBinding()]
    param(
        [Parameter()]
        [version] $MinimumVersion = '5.0.0'
    )

    $pester = Get-Module -ListAvailable -Name Pester |
        Sort-Object Version -Descending |
        Select-Object -First 1

    if (-not $pester -or $pester.Version -lt $MinimumVersion) {
        Write-Host "Installing Pester >= $MinimumVersion (CurrentUser scope)..."
        Install-Module -Name Pester -Scope CurrentUser -Force -MinimumVersion $MinimumVersion
    }

    Import-Module -Name Pester -MinimumVersion $MinimumVersion -Force
}

# Ensure output folder exists (for CI artifacts)
$resultsDir = Split-Path -Path $TestResultsPath -Parent
if ($resultsDir -and -not (Test-Path -Path $resultsDir)) {
    New-Item -Path $resultsDir -ItemType Directory -Force | Out-Null
}

Test-Pester -MinimumVersion '5.0.0'

$config = New-PesterConfiguration
$config.Run.Path = $TestPath
$config.Run.Exit = $true
$config.Output.Verbosity = 'Detailed'

if ($CI) {
    $config.TestResult.Enabled = $true
    $config.TestResult.OutputFormat = 'NUnitXml'
    $config.TestResult.OutputPath = $TestResultsPath
}

Invoke-Pester -Configuration $config

# Generate Cmdlet Documentation after tests pass

Write-Host "`nGenerating Cmdlet reference documentation..."
& .\tools\Generate-IdleCmdletReference.ps1

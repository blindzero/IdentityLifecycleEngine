<#
.SYNOPSIS
Legacy wrapper for running IdLE Pester tests.

.DESCRIPTION
DEPRECATED: Use './tools/Invoke-IdlePesterTests.ps1' instead.

This wrapper exists for backward compatibility because older documentation and
workflows still reference 'run-tests.ps1'. It will be removed in a future release.

.PARAMETER TestPath
Path to the tests folder. Defaults to 'tests'.

.PARAMETER CI
Enables CI mode. Passed through to Invoke-IdlePesterTests.ps1.

.PARAMETER TestResultsPath
Path to the NUnitXml test results file. Passed through to Invoke-IdlePesterTests.ps1.

.EXAMPLE
pwsh -NoProfile -File ./tools/run-tests.ps1 -CI
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
    [string] $TestResultsPath = 'artifacts/test-results.xml'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$targetScript = Join-Path -Path $PSScriptRoot -ChildPath 'Invoke-IdlePesterTests.ps1'
if (-not (Test-Path -LiteralPath $targetScript)) {
    throw "Missing required script '$targetScript'. Ensure your working copy includes 'tools/Invoke-IdlePesterTests.ps1'."
}

if (-not $CI) {
    Write-Warning "DEPRECATED: './tools/run-tests.ps1' is deprecated. Use './tools/Invoke-IdlePesterTests.ps1' instead."
}

& $targetScript `
    -TestPath $TestPath `
    -CI:$CI `
    -TestResultsPath $TestResultsPath

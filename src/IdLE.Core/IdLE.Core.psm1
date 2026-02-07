#requires -Version 7.0

Set-StrictMode -Version Latest

# Internal module warning: discourage direct import unless explicitly allowed
# Suppress warning if:
# - IDLE_ALLOW_INTERNAL_IMPORT is set (IdLE meta-module sets this automatically)
# - Module is in a standard PSModulePath location (published/installed layout)
if (-not $env:IDLE_ALLOW_INTERNAL_IMPORT) {
    # Check if module is in a PSModulePath directory (published/installed scenario)
    $modulePaths = $env:PSModulePath -split [System.IO.Path]::PathSeparator
    $inPSModulePath = $false
    foreach ($path in $modulePaths) {
        if ($PSScriptRoot -like "$path*") {
            $inPSModulePath = $true
            break
        }
    }
    
    # Only warn if not in PSModulePath (repo/zip scenario with direct import)
    if (-not $inPSModulePath) {
        Write-Warning "IdLE.Core is an internal/unsupported module. Import 'IdLE' instead for the supported public API. To bypass: `$env:IDLE_ALLOW_INTERNAL_IMPORT = '1'"
    }
}

$PublicPath = Join-Path -Path $PSScriptRoot -ChildPath 'Public'
$PrivatePath = Join-Path -Path $PSScriptRoot -ChildPath 'Private'

foreach ($path in @($PrivatePath, $PublicPath)) {
    if (-not (Test-Path -Path $path)) {
        continue
    }

    Get-ChildItem -Path $path -Filter '*.ps1' -File |
        Sort-Object -Property FullName |
        ForEach-Object {
            . $_.FullName
        }
}

# Core exports selected factory functions. The meta module (IdLE) exposes the public API.
Export-ModuleMember -Function @(
    'New-IdleLifecycleRequestObject',
    'Test-IdleWorkflowDefinitionObject',
    'New-IdlePlanObject',
    'Invoke-IdlePlanObject',
    'Export-IdlePlanObject',
    'New-IdleAuthSessionBroker',
    'Invoke-IdleProviderMethod',
    'Test-IdleProviderMethodParameter'
) -Alias @()

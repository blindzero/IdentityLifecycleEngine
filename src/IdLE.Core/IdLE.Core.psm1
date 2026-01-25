#requires -Version 7.0

Set-StrictMode -Version Latest

# Internal module warning: discourage direct import unless explicitly allowed
# Suppress warning if IDLE_ALLOW_INTERNAL_IMPORT is set
# (IdLE meta-module sets this automatically; users can also set it for advanced scenarios)
if (-not $env:IDLE_ALLOW_INTERNAL_IMPORT) {
    Write-Warning "IdLE.Core is an internal/unsupported module. Import 'IdLE' instead for the supported public API. To bypass: `$env:IDLE_ALLOW_INTERNAL_IMPORT = '1'"
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
    'New-IdleAuthSessionBroker'
) -Alias @()

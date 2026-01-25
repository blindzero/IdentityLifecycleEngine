#requires -Version 7.0

Set-StrictMode -Version Latest

# Internal module warning: discourage direct import unless explicitly allowed
# Note: Warning is suppressed when loaded as a nested module of IdLE to avoid
# false positives in correct usage scenarios. Direct imports outside the IdLE
# ecosystem will not trigger a warning, but are unsupported per documentation.
if ($env:IDLE_WARN_INTERNAL_IMPORT -eq '1') {
    Write-Warning "IdLE.Core is an internal/unsupported module. Import 'IdLE' instead for the supported public API."
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

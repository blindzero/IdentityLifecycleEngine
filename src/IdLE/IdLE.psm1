#requires -Version 7.0

Set-StrictMode -Version Latest

# NestedModules in the manifest handle loading IdLE.Core and IdLE.Steps.Common
# PSModulePath bootstrap is performed by IdLE.Init.ps1 via ScriptsToProcess (before NestedModules load)

$PublicPath = Join-Path -Path $PSScriptRoot -ChildPath 'Public'
if (Test-Path -Path $PublicPath) {
    Get-ChildItem -Path $PublicPath -Filter '*.ps1' -File |
        Sort-Object -Property FullName |
        ForEach-Object {
            . $_.FullName
        }
}

# Export exactly the public API cmdlets (contract).
Export-ModuleMember -Function @(
    'Test-IdleWorkflow',
    'New-IdleLifecycleRequest',
    'New-IdlePlan',
    'Invoke-IdlePlan',
    'Export-IdlePlan',
    'New-IdleAuthSession'
)

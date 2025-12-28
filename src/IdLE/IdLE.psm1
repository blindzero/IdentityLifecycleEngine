#requires -Version 7.0

Set-StrictMode -Version Latest

$CoreManifestPath = Join-Path -Path $PSScriptRoot -ChildPath '..\IdLE.Core\IdLE.Core.psd1'
Import-Module -Name $CoreManifestPath -Force -ErrorAction Stop

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
    'Invoke-IdlePlan'
)

#requires -Version 7.0
Set-StrictMode -Version Latest

$PublicPath = Join-Path -Path $PSScriptRoot -ChildPath 'Public'
if (Test-Path -Path $PublicPath) {
    Get-ChildItem -Path $PublicPath -Filter '*.ps1' -File |
        Sort-Object -Property FullName |
        ForEach-Object { . $_.FullName }
}

Export-ModuleMember -Function @(
    'Invoke-IdleStepEmitEvent'
)

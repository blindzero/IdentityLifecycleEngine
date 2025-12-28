#requires -Version 7.0

Set-StrictMode -Version Latest

$PublicPath  = Join-Path -Path $PSScriptRoot -ChildPath 'Public'
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
    'New-IdleLifecycleRequestCore'
) -Alias @()

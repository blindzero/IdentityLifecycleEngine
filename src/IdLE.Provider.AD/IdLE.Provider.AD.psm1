#requires -Version 7.0
Set-StrictMode -Version Latest

$PrivatePath = Join-Path -Path $PSScriptRoot -ChildPath 'Private'
if (Test-Path -Path $PrivatePath) {
    $privateScripts = @(Get-ChildItem -Path $PrivatePath -Filter '*.ps1' -File | Sort-Object -Property FullName)
    foreach ($script in $privateScripts) {
        . $script.FullName
    }
}

$PublicPath = Join-Path -Path $PSScriptRoot -ChildPath 'Public'
if (Test-Path -Path $PublicPath) {
    $publicScripts = @(Get-ChildItem -Path $PublicPath -Filter '*.ps1' -File | Sort-Object -Property FullName)
    foreach ($script in $publicScripts) {
        . $script.FullName
    }
}

Export-ModuleMember -Function @(
    'New-IdleADIdentityProvider'
)

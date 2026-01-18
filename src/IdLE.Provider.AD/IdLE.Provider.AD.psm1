#requires -Version 7.0

Set-StrictMode -Version Latest

# Validate ActiveDirectory module availability at module load time (best effort)
# The adapter will perform hard validation when instantiated
if ($PSVersionTable.Platform -eq 'Win32NT' -or $PSVersionTable.Platform -eq 'Windows') {
    if (-not (Get-Module -Name ActiveDirectory -ListAvailable)) {
        Write-Warning "IdLE.Provider.AD requires the ActiveDirectory module (RSAT). Install it with: Install-WindowsFeature -Name RSAT-AD-PowerShell (Windows Server) or Get-WindowsCapability -Online -Name 'Rsat.ActiveDirectory*' | Add-WindowsCapability -Online (Windows 10/11)"
    }
}

$PrivatePath = Join-Path -Path $PSScriptRoot -ChildPath 'Private'
if (Test-Path -Path $PrivatePath) {

    # Materialize first to avoid enumeration issues during import.
    $privateScripts = @(Get-ChildItem -Path $PrivatePath -Filter '*.ps1' -File | Sort-Object -Property FullName)

    foreach ($script in $privateScripts) {
        . $script.FullName
    }
}

$PublicPath = Join-Path -Path $PSScriptRoot -ChildPath 'Public'
if (Test-Path -Path $PublicPath) {

    # Materialize first to avoid enumeration issues during import.
    $publicScripts = @(Get-ChildItem -Path $PublicPath -Filter '*.ps1' -File | Sort-Object -Property FullName)

    foreach ($script in $publicScripts) {
        . $script.FullName
    }
}

Export-ModuleMember -Function @(
    'New-IdleADIdentityProvider'
)

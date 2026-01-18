#requires -Version 7.0

Set-StrictMode -Version Latest

# Validate ActiveDirectory module availability at module load time (best effort, non-blocking)
# The adapter will perform hard validation when instantiated
# Module import will succeed even if ActiveDirectory is not available to allow unit tests and
# cross-platform development. Provider instantiation will fail with clear error if AD module is missing.
if ($PSVersionTable.Platform -eq 'Win32NT' -or $PSVersionTable.Platform -eq 'Windows') {
    if (-not (Get-Module -Name ActiveDirectory -ListAvailable)) {
        Write-Verbose "IdLE.Provider.AD: ActiveDirectory module not found. The provider will require RSAT/ActiveDirectory at runtime."
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

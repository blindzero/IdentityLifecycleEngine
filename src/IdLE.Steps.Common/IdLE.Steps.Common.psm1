#requires -Version 7.0
Set-StrictMode -Version Latest

# Internal module warning: discourage direct import unless explicitly allowed
# Note: Warning is suppressed when loaded as a nested module of IdLE to avoid
# false positives in correct usage scenarios. Direct imports outside the IdLE
# ecosystem will not trigger a warning, but are unsupported per documentation.
if ($env:IDLE_WARN_INTERNAL_IMPORT -eq '1') {
    Write-Warning "IdLE.Steps.Common is an internal/unsupported module. Import 'IdLE' instead for the supported public API."
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
    'Get-IdleStepMetadataCatalog',
    'Invoke-IdleStepEmitEvent',
    'Invoke-IdleStepEnsureAttribute',
    'Invoke-IdleStepEnsureEntitlement',
    'Invoke-IdleStepCreateIdentity',
    'Invoke-IdleStepDisableIdentity',
    'Invoke-IdleStepEnableIdentity',
    'Invoke-IdleStepMoveIdentity',
    'Invoke-IdleStepDeleteIdentity'
)

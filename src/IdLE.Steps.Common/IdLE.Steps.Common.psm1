#requires -Version 7.0
Set-StrictMode -Version Latest

$PublicPath = Join-Path -Path $PSScriptRoot -ChildPath 'Public'
if (Test-Path -Path $PublicPath) {

    # Materialize first to avoid enumeration issues during import.
    $publicScripts = @(Get-ChildItem -Path $PublicPath -Filter '*.ps1' -File | Sort-Object -Property FullName)

    foreach ($script in $publicScripts) {
        . $script.FullName
    }
}

Export-ModuleMember -Function @(
    'Invoke-IdleStepEmitEvent',
    'Invoke-IdleStepEnsureAttribute',
    'Invoke-IdleStepEnsureEntitlement',
    'Invoke-IdleStepCreateIdentity',
    'Invoke-IdleStepDisableIdentity',
    'Invoke-IdleStepEnableIdentity',
    'Invoke-IdleStepMoveIdentity',
    'Invoke-IdleStepDeleteIdentity'
)

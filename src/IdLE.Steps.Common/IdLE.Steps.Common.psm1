#requires -Version 7.0
Set-StrictMode -Version Latest

# Internal module warning: discourage direct import unless explicitly allowed
# Suppress warning if IDLE_ALLOW_INTERNAL_IMPORT is set
# (IdLE meta-module sets this automatically; users can also set it for advanced scenarios)
if (-not $env:IDLE_ALLOW_INTERNAL_IMPORT) {
    Write-Warning "IdLE.Steps.Common is an internal/unsupported module. Import 'IdLE' instead for the supported public API. To bypass: set IDLE_ALLOW_INTERNAL_IMPORT=1."
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

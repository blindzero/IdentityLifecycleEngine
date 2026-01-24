#requires -Version 7.0
Set-StrictMode -Version Latest

# Import private helper functions from IdLE.Steps.Common
$commonModule = Get-Module -Name 'IdLE.Steps.Common'
if ($null -ne $commonModule) {
    $commonPrivatePath = Join-Path -Path $commonModule.ModuleBase -ChildPath 'Private'
    if (Test-Path -Path $commonPrivatePath) {
        $privateScripts = @(Get-ChildItem -Path $commonPrivatePath -Filter '*.ps1' -File | Sort-Object -Property FullName)
        foreach ($script in $privateScripts) {
            . $script.FullName
        }
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
    'Invoke-IdleStepTriggerDirectorySync'
)

#requires -Version 7.0
Set-StrictMode -Version Latest

$script:ModuleRoot = $PSScriptRoot

# Dot-source Public functions
$PublicScripts = Get-ChildItem -Path (Join-Path $script:ModuleRoot 'Public') -Filter '*.ps1' -ErrorAction SilentlyContinue
foreach ($script in ($PublicScripts | Sort-Object Name)) {
    . $script.FullName
}

# Dot-source Private functions
$PrivateScripts = Get-ChildItem -Path (Join-Path $script:ModuleRoot 'Private') -Filter '*.ps1' -ErrorAction SilentlyContinue
foreach ($script in ($PrivateScripts | Sort-Object Name)) {
    . $script.FullName
}

# Export Public functions
Export-ModuleMember -Function $PublicScripts.BaseName

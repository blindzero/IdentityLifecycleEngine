#requires -Version 7.0

Set-StrictMode -Version Latest

# Note: Microsoft Graph API access is provided by the host via AuthSessionBroker.
# No external module dependencies are required at module load time.
# The provider uses direct REST API calls to Microsoft Graph v1.0 endpoints.

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
    'New-IdleEntraIDIdentityProvider'
)

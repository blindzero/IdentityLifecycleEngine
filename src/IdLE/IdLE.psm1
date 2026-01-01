#requires -Version 7.0

Set-StrictMode -Version Latest

# region Bootstrap - ensure core module is loaded
# This meta module provides a stable entrypoint. It ensures IdLE.Core is loaded
# so that users only need to import "IdLE" regardless of installation method.

$script:IdleCoreModuleName = 'IdLE.Core'

function Import-IdleCoreModule {
    [CmdletBinding()]
    param()

    # Already loaded -> nothing to do
    if (Get-Module -Name $script:IdleCoreModuleName) {
        return
    }

    # 1) Preferred: resolve via PSModulePath (PowerShell Gallery or user installed modules)
    try {
        Import-Module -Name $script:IdleCoreModuleName -ErrorAction Stop
        return
    }
    catch {
        # Continue with local fallback
    }

    # 2) Fallback: repo clone layout (IdLE and IdLE.Core side-by-side under /src)
    $coreManifestPath = Join-Path -Path $PSScriptRoot -ChildPath '..\IdLE.Core\IdLE.Core.psd1'

    if (-not (Test-Path -Path $coreManifestPath)) {
        throw "Failed to load '$($script:IdleCoreModuleName)'. Module was not found via PSModulePath and local fallback path does not exist: $coreManifestPath"
    }

    Import-Module -Name $coreManifestPath -Force -ErrorAction Stop
}

Import-IdleCoreModule

$PublicPath = Join-Path -Path $PSScriptRoot -ChildPath 'Public'
if (Test-Path -Path $PublicPath) {
    Get-ChildItem -Path $PublicPath -Filter '*.ps1' -File |
        Sort-Object -Property FullName |
        ForEach-Object {
            . $_.FullName
        }
}

# Export exactly the public API cmdlets (contract).
Export-ModuleMember -Function @(
    'Test-IdleWorkflow',
    'New-IdleLifecycleRequest',
    'New-IdlePlan',
    'Invoke-IdlePlan',
    'Export-IdlePlan'
)

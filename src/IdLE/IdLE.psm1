#requires -Version 7.0

Set-StrictMode -Version Latest

# region PSModulePath Bootstrap for Repo/Zip Layouts
# Add src/ directory to PSModulePath if we detect a repo/zip layout
# This must run before attempting to import dependencies

if ($PSScriptRoot) {
    $parentDir = Split-Path -Path $PSScriptRoot -Parent
    
    # Check if parent directory is named 'src' (repo/zip layout indicator)
    if ((Split-Path -Leaf -Path $parentDir) -eq 'src') {
        $srcPath = $parentDir
        
        # Check if src is already in PSModulePath (idempotent)
        $currentPSModulePath = $env:PSModulePath
        $pathSeparator = [System.IO.Path]::PathSeparator
        $paths = $currentPSModulePath -split [regex]::Escape($pathSeparator)
        
        $alreadyInPath = $false
        foreach ($p in $paths) {
            if ($p) {
                try {
                    $resolvedP = (Resolve-Path -Path $p -ErrorAction SilentlyContinue).Path
                    $resolvedSrc = (Resolve-Path -Path $srcPath -ErrorAction SilentlyContinue).Path
                    if ($resolvedP -and $resolvedSrc -and $resolvedP -eq $resolvedSrc) {
                        $alreadyInPath = $true
                        break
                    }
                } catch {
                    # Ignore resolution errors
                }
            }
        }
        
        if (-not $alreadyInPath) {
            # Add src to PSModulePath at process scope (session-only, non-persistent)
            $env:PSModulePath = $srcPath + $pathSeparator + $currentPSModulePath
        }
    }
}
# endregion

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
        Write-Verbose "Failed to import '$($script:IdleCoreModuleName)' from PSModulePath: $($_.Exception.Message)"
    }

    # 2) Fallback: repo clone layout (IdLE and IdLE.Core side-by-side under /src)
    $coreManifestPath = Join-Path -Path $PSScriptRoot -ChildPath '..\IdLE.Core\IdLE.Core.psd1'

    if (-not (Test-Path -Path $coreManifestPath)) {
        throw "Failed to load '$($script:IdleCoreModuleName)'. Module not found in PSModulePath and local fallback path does not exist: $coreManifestPath"
    }

    Import-Module -Name $coreManifestPath -Force -ErrorAction Stop
}


# region Bootstrap - ensure built-in step packs are loaded
# The core engine is step-agnostic. This meta module provides a batteries-included
# experience by importing first-party step packs where available.

$script:IdleBuiltInStepsModuleName = 'IdLE.Steps.Common'

function Import-IdleBuiltInStepsModule {
    [CmdletBinding()]
    param()

    # Already loaded -> nothing to do
    if (Get-Module -Name $script:IdleBuiltInStepsModuleName) {
        return
    }

    # 1) Try normal module resolution (e.g. installed from PSGallery)
    try {
        Import-Module -Name $script:IdleBuiltInStepsModuleName -ErrorAction Stop
        return
    }
    catch {
        # Continue with local fallback
        Write-Verbose "Failed to import '$($script:IdleBuiltInStepsModuleName)' from PSModulePath: $($_.Exception.Message)"
    }

    # 2) Fallback: repo clone layout (IdLE and packs side-by-side under /src)
    $stepsManifestPath = Join-Path -Path $PSScriptRoot -ChildPath '..\IdLE.Steps.Common\IdLE.Steps.Common.psd1'

    if (-not (Test-Path -Path $stepsManifestPath)) {
        Write-Verbose "Built-in steps module '$($script:IdleBuiltInStepsModuleName)' not found. Skipping import. Expected path: $stepsManifestPath"
        return
    }

    Import-Module -Name $stepsManifestPath -Force -ErrorAction Stop
}
# endregion

Import-IdleCoreModule
Import-IdleBuiltInStepsModule

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
    'Export-IdlePlan',
    'New-IdleAuthSession'
)

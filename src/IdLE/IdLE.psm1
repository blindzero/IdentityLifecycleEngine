#requires -Version 7.0

Set-StrictMode -Version Latest

# NestedModules in the manifest handle loading IdLE.Core and IdLE.Steps.Common
# PSModulePath bootstrap happens at the end of this file (after NestedModules are loaded)

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

# region PSModulePath Bootstrap for Repo/Zip Layouts (for subsequent imports)
# This runs AFTER NestedModules are loaded to enable name-based imports of providers and optional steps

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

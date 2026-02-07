# IdLE Module Initialization Script
# This script runs via ScriptsToProcess BEFORE NestedModules are imported

# Set environment variable to suppress internal module warnings during correct nested load
$env:IDLE_ALLOW_INTERNAL_IMPORT = '1'

# region PSModulePath Bootstrap for Repo/Zip Layouts  
# Add src/ directory to PSModulePath to enable name-based imports
# This runs BEFORE NestedModules are loaded from relative paths
# Enables subsequent: Import-Module IdLE.Provider.* and Import-Module IdLE.Steps.* by name
# 
# Note: This bootstrap is only needed in repo/zip layouts. For PSGallery published modules,
# this script and ScriptsToProcess are removed by the packaging tool.

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
                    # Non-fatal: path resolution can fail for invalid entries.
                    Write-Verbose -Message "Skipping unresolved PSModulePath entry: $p"
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

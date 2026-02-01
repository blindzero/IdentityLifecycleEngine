# IdLE Module Initialization Script
# This script runs via ScriptsToProcess BEFORE RequiredModules are imported (but after manifest validation)

# Repo/Zip bootstrap: Add src folder to PSModulePath if detected
# This enables name-based module discovery in repo/zip layouts

if ($PSScriptRoot) {
    $idleModulePath = $PSScriptRoot
    $parentDir = Split-Path -Path $idleModulePath -Parent
    
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

# Set environment variable to suppress internal module warnings during correct nested load
$env:IDLE_ALLOW_INTERNAL_IMPORT = '1'

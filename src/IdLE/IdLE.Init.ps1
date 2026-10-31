# IdLE Module Initialization Script
# This script runs via ScriptsToProcess BEFORE NestedModules are imported

# Set environment variable to suppress internal module warnings during correct nested load
$env:IDLE_ALLOW_INTERNAL_IMPORT = '1'

# region PSModulePath Bootstrap for Repo/Zip Layouts
# Add src/ directory to PSModulePath to enable name-based imports
# This runs BEFORE NestedModules are loaded from relative paths
# Enables name-based resolution of RequiredModules (e.g. IdLE.Core) when single modules
# under src/ are imported directly (development and tests).
#
# Note: This bootstrap is only needed in repo/zip layouts. In the bundled package
# (PSGallery) the parent folder is not named 'src', so nothing is changed.

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

# region Mixed-version guard
# The IdLE bundle ships all first-party modules as nested modules. A standalone IdLE.* module
# (e.g. a discontinued IdLE.Provider.AD package from the PowerShell Gallery) that is already
# loaded into the session could shadow the bundled one and mix versions. Fail early instead.
#
# Runs in a child scope because ScriptsToProcess executes in the caller's session state.
& {
    if (-not $PSScriptRoot) {
        return
    }

    $manifestPath = Join-Path -Path $PSScriptRoot -ChildPath 'IdLE.psd1'
    $manifest = Import-PowerShellDataFile -LiteralPath $manifestPath

    $comparison = if ($IsWindows) { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal }
    $separators = [char[]]@([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)

    # Map bundled module name -> expected module folder (from the NestedModules entries).
    $bundled = @{}
    foreach ($entry in @($manifest.NestedModules)) {
        $relative = ([string]$entry) -replace '[\\/]', [System.IO.Path]::DirectorySeparatorChar
        $nestedManifest = [System.IO.Path]::GetFullPath((Join-Path -Path $PSScriptRoot -ChildPath $relative))
        $name = [System.IO.Path]::GetFileNameWithoutExtension($nestedManifest)
        $bundled[$name] = (Split-Path -Path $nestedManifest -Parent).TrimEnd($separators)
    }

    $foreign = @(
        Get-Module -All -Name 'IdLE.*' | Where-Object {
            $bundled.ContainsKey($_.Name) -and
            -not [string]::Equals($_.ModuleBase.TrimEnd($separators), $bundled[$_.Name], $comparison)
        } | Sort-Object -Property Name -Unique
    )

    if ($foreign.Count -gt 0) {
        $details = ($foreign | ForEach-Object { "  - $($_.Name) $($_.Version) ($($_.ModuleBase))" }) -join [Environment]::NewLine
        $names = ($foreign.Name | ForEach-Object { "'$_'" }) -join ', '

        $message = @(
            "IdLE: standalone IdLE modules are already loaded in this session and conflict with the bundled modules of 'IdLE':"
            $details
            "All first-party modules are part of the 'IdLE' package. Remove the standalone modules from the session and import IdLE again:"
            "  Remove-Module -Name $names -Force"
            "If the standalone packages are installed from the PowerShell Gallery, uninstall them:"
            "  Uninstall-Module -Name $names -AllVersions"
        ) -join [Environment]::NewLine

        throw $message
    }
}
# endregion

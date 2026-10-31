function Test-IdleFirstPartyModule {
    <#
    .SYNOPSIS
    Returns $true if a module is a first-party module of the loaded IdLE bundle.

    .DESCRIPTION
    A module is first-party if it is the IdLE bundle module itself or one of its NestedModules, loaded
    from the folder the bundle manifest points to. Ownership is never inferred from module names.

    The folders are derived from the bundle manifest (same rule as the mixed-version guard in
    IdLE.Init.ps1), so this works for both the repository layout (src/IdLE.Core next to src/IdLE)
    and the packaged layout (IdLE/Modules/IdLE.Core).

    Returns $false if no IdLE bundle is loaded.

    .PARAMETER Module
    The module to check.

    .OUTPUTS
    System.Boolean
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.PSModuleInfo] $Module
    )

    $bundle = Get-Module -Name 'IdLE' -All | Select-Object -First 1
    if ($null -eq $bundle -or [string]::IsNullOrWhiteSpace($Module.ModuleBase)) {
        return $false
    }

    $comparison = if ($IsWindows) { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal }
    $separators = [char[]]@([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)

    $bundleBase = [System.IO.Path]::GetFullPath($bundle.ModuleBase).TrimEnd($separators)
    $moduleBase = [System.IO.Path]::GetFullPath($Module.ModuleBase).TrimEnd($separators)

    if ($Module.Name -eq $bundle.Name) {
        return [string]::Equals($moduleBase, $bundleBase, $comparison)
    }

    $manifestPath = Join-Path -Path $bundleBase -ChildPath "$($bundle.Name).psd1"
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        return $false
    }

    $manifest = Import-PowerShellDataFile -LiteralPath $manifestPath
    foreach ($entry in @($manifest.NestedModules)) {
        # Manifest entries use '\'; normalize so the path also resolves on Linux/macOS.
        $relative = ([string]$entry) -replace '[\\/]', [System.IO.Path]::DirectorySeparatorChar
        $nestedManifest = [System.IO.Path]::GetFullPath((Join-Path -Path $bundleBase -ChildPath $relative))

        if ([System.IO.Path]::GetFileNameWithoutExtension($nestedManifest) -ne $Module.Name) {
            continue
        }

        $expectedBase = (Split-Path -Path $nestedManifest -Parent).TrimEnd($separators)
        return [string]::Equals($moduleBase, $expectedBase, $comparison)
    }

    return $false
}

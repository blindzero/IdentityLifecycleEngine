<#
.SYNOPSIS
Computes the dependency-ordered list of IdLE modules for publishing to PowerShell Gallery.

.DESCRIPTION
Analyzes module manifests in the repository to determine dependencies (RequiredModules/NestedModules)
and returns modules in an order where dependencies are published before dependent modules.

This ensures PowerShell Gallery can validate RequiredModules during publish.

.PARAMETER RepoRootPath
Repository root path. Defaults to the parent folder of this script directory.

.PARAMETER IncludeModule
Optional filter to include only specific modules. If not specified, includes all publishable modules.

.OUTPUTS
System.String[]
Array of module names in dependency order (dependencies first).

.EXAMPLE
pwsh -NoProfile -File ./tools/Get-IdleModulePublishOrder.ps1

.EXAMPLE
$order = & ./tools/Get-IdleModulePublishOrder.ps1
foreach ($module in $order) { Write-Host "Publish: $module" }
#>

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string] $RepoRootPath = (Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')).Path,

    [Parameter()]
    [string[]] $IncludeModule = $null
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-IdleModuleManifests {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $RepoRootPath
    )

    $srcRoot = Join-Path -Path $RepoRootPath -ChildPath 'src'
    if (-not (Test-Path -LiteralPath $srcRoot)) {
        throw "Source folder not found: $srcRoot"
    }

    # Find all module manifests matching pattern: src/<ModuleName>/<ModuleName>.psd1
    $manifests = Get-ChildItem -Path $srcRoot -Directory |
        ForEach-Object {
            $moduleName = $_.Name
            $manifestPath = Join-Path -Path $_.FullName -ChildPath "$moduleName.psd1"
            if (Test-Path -LiteralPath $manifestPath) {
                [pscustomobject]@{
                    Name         = $moduleName
                    Path         = $manifestPath
                    Dependencies = @()
                }
            }
        }

    # Parse dependencies from each manifest
    foreach ($module in $manifests) {
        try {
            $data = Import-PowerShellDataFile -LiteralPath $module.Path -ErrorAction Stop
        }
        catch {
            Write-Warning "Failed to parse manifest: $($module.Path) - $($_.Exception.Message)"
            continue
        }

        $deps = @()

        # Check RequiredModules
        if ($data.ContainsKey('RequiredModules') -and $data.RequiredModules) {
            foreach ($req in $data.RequiredModules) {
                $depName = if ($req -is [hashtable]) { $req.ModuleName } else { $req }
                if ($depName -like 'IdLE*') {
                    $deps += $depName
                }
            }
        }

        # Check NestedModules for relative path references (convert to module names)
        if ($data.ContainsKey('NestedModules') -and $data.NestedModules) {
            foreach ($nested in $data.NestedModules) {
                if ($nested -match '\\(IdLE[^\\]+)\\([^\\]+)\.psd1$') {
                    $deps += $Matches[2]
                }
                elseif ($nested -match '/(IdLE[^/]+)/([^/]+)\.psd1$') {
                    $deps += $Matches[2]
                }
            }
        }

        $module.Dependencies = $deps | Select-Object -Unique
    }

    return $manifests
}

function Get-TopologicalSort {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]] $Modules
    )

    $sorted = New-Object System.Collections.Generic.List[string]
    $visited = @{}
    $visiting = @{}

    function Visit-Module {
        param([string] $Name)

        if ($visited.ContainsKey($Name)) {
            return
        }

        if ($visiting.ContainsKey($Name)) {
            throw "Circular dependency detected involving module: $Name"
        }

        $visiting[$Name] = $true

        $module = $Modules | Where-Object { $_.Name -eq $Name } | Select-Object -First 1
        if ($module) {
            foreach ($dep in $module.Dependencies) {
                Visit-Module -Name $dep
            }
        }

        $visiting.Remove($Name)
        $visited[$Name] = $true
        $sorted.Add($Name)
    }

    foreach ($module in $Modules) {
        Visit-Module -Name $module.Name
    }

    return , $sorted.ToArray()
}

# Main execution
$manifests = Get-IdleModuleManifests -RepoRootPath $RepoRootPath

# Filter if requested
if ($IncludeModule -and $IncludeModule.Count -gt 0) {
    $manifests = $manifests | Where-Object { $IncludeModule -contains $_.Name }
}

if (-not $manifests -or $manifests.Count -eq 0) {
    throw "No module manifests found in: $(Join-Path -Path $RepoRootPath -ChildPath 'src')"
}

# Compute topological sort (dependencies before dependents)
$publishOrder = Get-TopologicalSort -Modules $manifests

# Return the order
return , $publishOrder

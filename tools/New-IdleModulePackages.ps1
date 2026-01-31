<#
.SYNOPSIS
Creates publishable module packages for all IdLE modules.

.DESCRIPTION
Builds individual staging folders for each IdLE module suitable for publishing to PowerShell Gallery.
Each module is packaged separately with proper dependencies declared in the manifest.

.PARAMETER RepoRootPath
Repository root path. Defaults to the parent folder of this script directory.

.PARAMETER OutputDirectory
Target folder for the staged packages. Defaults to '<RepoRootPath>/artifacts/modules'.

.PARAMETER ModuleNames
Names of modules to package. Defaults to all publishable modules.

.PARAMETER Clean
If set, deletes the OutputDirectory before staging the packages.

.OUTPUTS
System.IO.DirectoryInfo[]

.EXAMPLE
pwsh -NoProfile -File ./tools/New-IdleModulePackages.ps1

.EXAMPLE
pwsh -NoProfile -File ./tools/New-IdleModulePackages.ps1 -Clean
#>

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string] $RepoRootPath = (Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')).Path,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string] $OutputDirectory,

    [Parameter()]
    [string[]] $ModuleNames = $null,

    [Parameter()]
    [switch] $Clean
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Default ModuleNames to all publishable modules if not specified
if ($null -eq $ModuleNames -or $ModuleNames.Count -eq 0) {
    $ModuleNames = @(
        'IdLE.Core',
        'IdLE.Steps.Common',
        'IdLE.Steps.DirectorySync',
        'IdLE.Steps.Mailbox',
        'IdLE.Provider.AD',
        'IdLE.Provider.EntraID',
        'IdLE.Provider.ExchangeOnline',
        'IdLE.Provider.DirectorySync.EntraConnect',
        'IdLE.Provider.Mock',
        'IdLE'
    )
}

function Resolve-IdleRepoRoot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    $resolved = (Resolve-Path -LiteralPath $Path).Path

    $idleManifest = Join-Path -Path $resolved -ChildPath 'src/IdLE/IdLE.psd1'
    if (-not (Test-Path -LiteralPath $idleManifest)) {
        throw "RepoRootPath does not look like the IdLE repository root (missing 'src/IdLE/IdLE.psd1'): $resolved"
    }

    return $resolved
}

function Initialize-IdleDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter()]
        [switch] $ForceClean
    )

    if ($ForceClean -and (Test-Path -LiteralPath $Path)) {
        Remove-Item -LiteralPath $Path -Recurse -Force
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -ItemType Directory -Force | Out-Null
    }
}

function Copy-IdleModuleFolder {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $SourcePath,

        [Parameter(Mandatory)]
        [string] $DestinationPath,

        [Parameter()]
        [switch] $TransformForGallery
    )

    if (-not (Test-Path -LiteralPath $SourcePath)) {
        throw "Source module folder not found: $SourcePath"
    }

    Initialize-IdleDirectory -Path $DestinationPath

    # Copy content of the module folder, not the folder itself, to keep predictable structure.
    Copy-Item -Path (Join-Path -Path $SourcePath -ChildPath '*') -Destination $DestinationPath -Recurse -Force

    # Transform IdLE manifest for PowerShell Gallery if needed
    if ($TransformForGallery) {
        $moduleName = Split-Path -Path $DestinationPath -Leaf
        $manifestPath = Join-Path -Path $DestinationPath -ChildPath "$moduleName.psd1"
        
        if (Test-Path -LiteralPath $manifestPath) {
            Convert-IdleManifestForGallery -ManifestPath $manifestPath
        }
    }
}

function Convert-IdleManifestForGallery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ManifestPath
    )

    $raw = Get-Content -LiteralPath $ManifestPath -Raw -ErrorAction Stop
    
    # Extract module name from manifest path
    $moduleName = [System.IO.Path]::GetFileNameWithoutExtension($ManifestPath)
    
    Write-Verbose "Converting $moduleName manifest for PowerShell Gallery"
    
    $updated = $raw
    
    # For IdLE meta-module, replace NestedModules with RequiredModules
    if ($moduleName -eq 'IdLE') {
        # Check if this manifest has NestedModules
        if ($raw -match '(?ms)^\s*NestedModules\s*=') {
            $requiredModules = @"
    RequiredModules = @(
        @{ ModuleName = 'IdLE.Core'; ModuleVersion = '0.9.1' },
        @{ ModuleName = 'IdLE.Steps.Common'; ModuleVersion = '0.9.1' }
    )
"@
            
            # Remove NestedModules block
            $pattern = '(?ms)^[ \t]*NestedModules[ \t]*=[ \t]*@\((?:.|\n)*?\)[ \t]*\r?\n'
            $updated = [regex]::Replace($updated, $pattern, '')
            
            # Add RequiredModules after ScriptsToProcess
            $insertAfter = '(?m)^[ \t]*ScriptsToProcess[ \t]*=.*\)[ \t]*\r?\n'
            if ($updated -match $insertAfter) {
                $updated = [regex]::Replace($updated, $insertAfter, "`$0`r`n$requiredModules`r`n", 1)
            }
            else {
                # Fallback: add after RootModule
                $insertAfter = '(?m)^[ \t]*RootModule[ \t]*=.*\r?\n'
                if ($updated -match $insertAfter) {
                    $updated = [regex]::Replace($updated, $insertAfter, "`$0`r`n$requiredModules`r`n", 1)
                }
            }
        }
    }
    # For IdLE.Steps.* modules (except Steps.Common), add RequiredModules for IdLE.Core and IdLE.Steps.Common
    elseif ($moduleName -match '^IdLE\.Steps\.(?!Common$)') {
        $requiredModules = @"
    RequiredModules   = @(
        @{ ModuleName = 'IdLE.Core'; ModuleVersion = '0.9.1' },
        @{ ModuleName = 'IdLE.Steps.Common'; ModuleVersion = '0.9.1' }
    )

"@
        # Add RequiredModules after PowerShellVersion
        $insertAfter = '(?m)^[ \t]*PowerShellVersion[ \t]*=.*\r?\n'
        if ($updated -match $insertAfter) {
            $updated = [regex]::Replace($updated, $insertAfter, "`$0`r`n$requiredModules", 1)
        }
    }
    # For IdLE.Steps.Common or IdLE.Provider.* modules, add RequiredModules for IdLE.Core only
    elseif ($moduleName -match '^IdLE\.(Steps\.Common|Provider\.)') {
        $requiredModules = @"
    RequiredModules   = @(
        @{ ModuleName = 'IdLE.Core'; ModuleVersion = '0.9.1' }
    )

"@
        # Add RequiredModules after PowerShellVersion
        $insertAfter = '(?m)^[ \t]*PowerShellVersion[ \t]*=.*\r?\n'
        if ($updated -match $insertAfter) {
            $updated = [regex]::Replace($updated, $insertAfter, "`$0`r`n$requiredModules", 1)
        }
    }
    
    if ($updated -ne $raw) {
        Set-Content -LiteralPath $ManifestPath -Value $updated -Encoding UTF8 -NoNewline
    }
}

# Defaults
$RepoRootPath = Resolve-IdleRepoRoot -Path $RepoRootPath

if (-not $PSBoundParameters.ContainsKey('OutputDirectory')) {
    $OutputDirectory = Join-Path -Path $RepoRootPath -ChildPath 'artifacts/modules'
}

$srcRoot = Join-Path -Path $RepoRootPath -ChildPath 'src'

Initialize-IdleDirectory -Path $OutputDirectory -ForceClean:$Clean

$packagedModules = @()

foreach ($moduleName in $ModuleNames) {
    $moduleSrc = Join-Path -Path $srcRoot -ChildPath $moduleName
    $moduleDst = Join-Path -Path $OutputDirectory -ChildPath $moduleName

    if (-not (Test-Path -LiteralPath $moduleSrc)) {
        Write-Warning "Module source not found: $moduleSrc - skipping"
        continue
    }

    Write-Host "Packaging module: $moduleName"
    Copy-IdleModuleFolder -SourcePath $moduleSrc -DestinationPath $moduleDst -TransformForGallery

    $packagedModules += Get-Item -LiteralPath $moduleDst
}

Write-Host ""
Write-Host "Packaged $($packagedModules.Count) module(s) to: $OutputDirectory"
$packagedModules | ForEach-Object { Write-Host "  - $($_.Name)" }

return , $packagedModules

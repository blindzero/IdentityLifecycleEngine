[CmdletBinding()]
param(
    # Path to the IdLE module manifest to import for documentation generation.
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string] $ModuleManifestPath,

    # Output folder for generated cmdlet Markdown files.
    # The folder will be created if it does not exist.
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string] $OutputFolder,

    # Optional: Create/overwrite an index Markdown file that links all generated cmdlet pages.
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string] $IndexPath,

    # Optional: Command names to exclude from generation (exact match).
    [Parameter()]
    [string[]] $ExcludeCommands = @(),

    # Install platyPS automatically if it is missing (requires internet access).
    [Parameter()]
    [switch] $InstallPlatyPS
)

<#
.SYNOPSIS
Generates Markdown reference documentation for IdLE cmdlets using platyPS.

.DESCRIPTION
This script imports the IdLE module from the current repository clone and then uses the classic
platyPS module (PowerShell Gallery) to generate Markdown reference pages for exported public cmdlets.

Important:
- This generator intentionally uses ONLY the classic 'platyPS' module and the cmdlet 'New-MarkdownHelp'.
- No fallback to 'Microsoft.PowerShell.PlatyPS' is implemented on purpose to avoid API instability.

Additionally, it generates an index page (docs/reference/cmdlets.md) that includes a table with cmdlet
links and their synopsis.

.PARAMETER ModuleManifestPath
Path to the IdLE module manifest (IdLE.psd1). Defaults to ./src/IdLE/IdLE.psd1 relative to this script.

.PARAMETER OutputFolder
Output folder for the per-cmdlet Markdown files. Defaults to ./docs/reference/cmdlets relative to this script.

.PARAMETER IndexPath
Path to the index Markdown file. Defaults to ./docs/reference/cmdlets.md relative to this script.

.PARAMETER ExcludeCommands
Command names to exclude (exact match). Useful if some exported commands are internal or experimental.

.PARAMETER InstallPlatyPS
If specified, installs platyPS automatically when it is not available. For CI pipelines, you may prefer
pre-installing dependencies and omitting this switch.

.EXAMPLE
pwsh ./tools/Generate-IdleCmdletReference.ps1

.EXAMPLE
pwsh ./tools/Generate-IdleCmdletReference.ps1 -InstallPlatyPS

.OUTPUTS
System.IO.FileInfo
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-IdleRepoPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Path
    )

    return (Resolve-Path -Path $Path).Path
}

function Import-IdlePlatyPS {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [switch] $AllowInstall
    )

    $moduleName = 'platyPS'

    if (Get-Module -ListAvailable -Name $moduleName) {
        Import-Module -Name $moduleName -ErrorAction Stop | Out-Null
        return
    }

    if (-not $AllowInstall) {
        throw "Required module '$moduleName' is not installed. Install it (PowerShell Gallery) or rerun with -InstallPlatyPS."
    }

    if (-not (Get-Command -Name Install-Module -ErrorAction SilentlyContinue)) {
        throw "Cannot auto-install '$moduleName' because 'Install-Module' is not available. Install '$moduleName' manually and retry."
    }

    Install-Module -Name $moduleName -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop | Out-Null
    Import-Module -Name $moduleName -ErrorAction Stop | Out-Null
}

function Get-IdleCmdletMetadata {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $ModuleName,

        [Parameter()]
        [string[]] $Exclude = @()
    )

    $cmds =
        Get-Command -Module $ModuleName -CommandType Function, Cmdlet -ErrorAction Stop |
        Where-Object { $_.Name -and $_.Name -notin $Exclude } |
        Sort-Object -Property Name -Unique

    foreach ($cmd in $cmds) {
        $help = $null
        try {
            $help = Get-Help -Name $cmd.Name -Full -ErrorAction Stop
        }
        catch {
            # Missing help should not fail generation; we reflect it in the synopsis.
        }

        $synopsis = ''
        if ($null -ne $help -and $help.Synopsis) {
            $synopsis = ($help.Synopsis | Out-String).Trim()
        }

        if ([string]::IsNullOrWhiteSpace($synopsis)) {
            $synopsis = 'No synopsis available (missing comment-based help).'
        }

        [pscustomobject]@{
            Name     = $cmd.Name
            Synopsis = $synopsis
        }
    }
}

function New-IdleCmdletIndexMarkdown {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $IndexPath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $OutputFolder,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [pscustomobject[]] $Cmdlets
    )

    $indexDir = Split-Path -Path $IndexPath -Parent
    if (-not (Test-Path -Path $indexDir)) {
        New-Item -Path $indexDir -ItemType Directory -Force | Out-Null
    }

    $timestampUtc = [DateTime]::UtcNow.ToString('yyyy-MM-dd HH:mm:ss "UTC"')

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('# Cmdlet Reference')
    $lines.Add('')
    $lines.Add('> Generated file. Do not edit by hand.')
    $lines.Add("> Source: tools/Generate-IdleCmdletReference.ps1")
    $lines.Add('')
    $lines.Add('This page links the generated per-cmdlet reference pages and includes their synopsis.')
    $lines.Add('')

    # Table header
    $lines.Add('| Cmdlet | Synopsis |')
    $lines.Add('| --- | --- |')

    foreach ($cmd in ($Cmdlets | Sort-Object -Property Name)) {
        $mdFile = Join-Path -Path $OutputFolder -ChildPath "$($cmd.Name).md"
        if (-not (Test-Path -Path $mdFile)) {
            continue
        }

        # Build a relative link for GitHub rendering.
        $relative = [System.IO.Path]::GetRelativePath($indexDir, $mdFile) -replace '\\', '/'

        # Escape table-sensitive characters in synopsis.
        $synopsis = ($cmd.Synopsis -replace '\|', '\|').Trim()

        $lines.Add("| [$($cmd.Name)]($relative) | $synopsis |")
    }
    $lines.Add("")

    Write-Verbose "Writing index file: $IndexPath"
    Set-Content -Path $IndexPath -Value ($lines -join "`n") -Encoding utf8 -NoNewline

    $indexFile = Get-Item -Path $IndexPath
    Write-Verbose "Index size: $($indexFile.Length) bytes"

    # Emit minimal, stable output (friendly for local runs and CI logs).
    "Generated cmdlet reference index: $($indexFile.FullName) ($($indexFile.Length) bytes)"
}

# Resolve defaults relative to this script to keep usage simple in a repo clone.
$repoRoot = Split-Path -Path $PSScriptRoot -Parent

if (-not $PSBoundParameters.ContainsKey('ModuleManifestPath')) {
    $ModuleManifestPath = Join-Path -Path $repoRoot -ChildPath 'src/IdLE/IdLE.psd1'
}
if (-not $PSBoundParameters.ContainsKey('OutputFolder')) {
    $OutputFolder = Join-Path -Path $repoRoot -ChildPath 'docs/reference/cmdlets'
}
if (-not $PSBoundParameters.ContainsKey('IndexPath')) {
    $IndexPath = Join-Path -Path $repoRoot -ChildPath 'docs/reference/cmdlets.md'
}

$ModuleManifestPath = Resolve-IdleRepoPath -Path $ModuleManifestPath

# Ensure output folder exists.
if (-not (Test-Path -Path $OutputFolder)) {
    New-Item -Path $OutputFolder -ItemType Directory -Force | Out-Null
}

# Load classic platyPS dependency (hard requirement).
Import-IdlePlatyPS -AllowInstall:$InstallPlatyPS

if (-not (Get-Command -Name 'New-MarkdownHelp' -ErrorAction SilentlyContinue)) {
    throw "platyPS is loaded but 'New-MarkdownHelp' is not available. Ensure you installed the classic 'platyPS' module."
}

# Import IdLE from working tree (deterministic doc generation).
Remove-Module -Name 'IdLE*' -Force -ErrorAction SilentlyContinue
Import-Module -Name $ModuleManifestPath -Force -ErrorAction Stop

$moduleNameForDocs = 'IdLE'

# Determine exported commands and synopsis (for index generation).
$cmdletMetadata = @(Get-IdleCmdletMetadata -ModuleName $moduleNameForDocs -Exclude $ExcludeCommands)

if ($cmdletMetadata.Count -eq 0) {
    throw "No exported commands found in module '$moduleNameForDocs'. Ensure the manifest exports public functions."
}

# Generate per-cmdlet Markdown using classic platyPS.
New-MarkdownHelp -Module $moduleNameForDocs -OutputFolder $OutputFolder -Force | Out-Null
Update-MarkdownHelp -Path $OutputFolder -Force | Out-Null

# Create/overwrite the index page (table with synopsis).
New-IdleCmdletIndexMarkdown -IndexPath $IndexPath -OutputFolder $OutputFolder -Cmdlets $cmdletMetadata

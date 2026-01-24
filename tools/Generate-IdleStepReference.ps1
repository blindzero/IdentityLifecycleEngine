[CmdletBinding()]
param(
    # Path to the IdLE module manifest to import for documentation generation.
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string] $ModuleManifestPath,

    # Markdown output path (will be created/overwritten).
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string] $OutputPath,

    # Restrict which step modules are scanned.
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string[]] $StepModules = @('IdLE.Steps.Common', 'IdLE.Steps.DirectorySync'),

    # Optional: Step function names to exclude (exact command names).
    [Parameter()]
    [string[]] $ExcludeCommands = @()
)

<#
.SYNOPSIS
Generates Markdown reference documentation for IdLE steps.

.DESCRIPTION
This script imports the IdLE module from the current repository clone and generates a Markdown
"Step Catalog" based on functions following the naming convention: Invoke-IdleStep<StepType>.

The generator uses comment-based help (Get-Help) as the primary source and adds a small amount of
heuristic extraction from the step source file (e.g., required With.* keys when they are defined
in a simple static pattern).

Important:
- Do not edit the generated file by hand. Update step help/source and regenerate.

.PARAMETER ModuleManifestPath
Path to the IdLE module manifest (IdLE.psd1). Defaults to ./src/IdLE/IdLE.psd1 relative to this script.

.PARAMETER OutputPath
Path to the generated Markdown file. Defaults to ./docs/reference/steps.md relative to this script.

.PARAMETER StepModules
Modules that contain step functions (IdLE.Steps.*).

.PARAMETER ExcludeCommands
Specific step function names to exclude (exact command names).

.EXAMPLE
pwsh ./tools/Generate-IdleStepReference.ps1

.OUTPUTS
System.String
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

function ConvertTo-IdleMarkdownSafeText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text
    )

    $normalized = $Text -replace "`r`n", "`n" -replace "`r", "`n"
    return $normalized.Trim()
}

function Get-IdleStepTypeFromCommandName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $CommandName
    )

    $m = [regex]::Match($CommandName, '^Invoke-IdleStep(?<Type>.+)$')
    if (-not $m.Success) {
        return $null
    }

    return $m.Groups['Type'].Value
}

function Get-IdleHelpSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $CommandName
    )

    try {
        return Get-Help -Name $CommandName -Full -ErrorAction Stop
    }
    catch {
        return $null
    }
}

function Get-IdleRequiredWithKeysFromSource {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [System.Management.Automation.CommandInfo] $CommandInfo
    )

    # Best-effort heuristic: detect patterns like:
    # foreach ($key in @('IdentityKey','Name','Value')) { ... }
    $filePath = $null
    if ($CommandInfo.ScriptBlock -and $CommandInfo.ScriptBlock.File) {
        $filePath = $CommandInfo.ScriptBlock.File
    }

    if ([string]::IsNullOrWhiteSpace($filePath) -or -not (Test-Path -Path $filePath)) {
        return @()
    }

    $content = Get-Content -Path $filePath -Raw -ErrorAction Stop

    $m = [regex]::Match($content, 'foreach\s*\(\s*\$key\s+in\s+@\((?<List>[^)]*)\)\s*\)', 'IgnoreCase')
    if (-not $m.Success) {
        return @()
    }

    $listText = $m.Groups['List'].Value
    $keys = [regex]::Matches($listText, "'(?<Key>[^']+)'") | ForEach-Object { $_.Groups['Key'].Value }

    return @($keys | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
}

function Get-IdleProviderMethodHintFromDescription {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $DescriptionText
    )

    # Best-effort extraction:
    # "must implement an EnsureAttribute method" -> EnsureAttribute
    $m = [regex]::Match($DescriptionText, 'must\s+implement\s+an?\s+(?<Method>[A-Za-z0-9_]+)\s+method', 'IgnoreCase')
    if (-not $m.Success) {
        return $null
    }

    return $m.Groups['Method'].Value
}

function ConvertTo-IdleStepMarkdownSection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [System.Management.Automation.CommandInfo] $CommandInfo
    )

    $commandName = $CommandInfo.Name
    $stepType = Get-IdleStepTypeFromCommandName -CommandName $commandName
    if ([string]::IsNullOrWhiteSpace($stepType)) {
        return $null
    }

    $help = Get-IdleHelpSafe -CommandName $commandName

    $synopsis = ''
    $description = ''

    if ($null -ne $help) {
        if ($help.Synopsis) {
            $synopsis = ConvertTo-IdleMarkdownSafeText -Text ($help.Synopsis | Out-String)
        }
        if ($help.Description -and $help.Description.Text) {
            $description = ConvertTo-IdleMarkdownSafeText -Text (($help.Description.Text -join "`n") | Out-String)
        }
    }

    if ([string]::IsNullOrWhiteSpace($synopsis)) {
        $synopsis = 'No synopsis available (missing comment-based help).'
    }

    $requiredWithKeys = @(Get-IdleRequiredWithKeysFromSource -CommandInfo $CommandInfo)
    $idempotent = 'Unknown'
    if ($description -match '(?i)\bidempotent\b') {
        $idempotent = 'Yes'
    }

    $providerMethod = Get-IdleProviderMethodHintFromDescription -DescriptionText $description
    $contracts = if ($providerMethod) { "Provider must implement method: $providerMethod" } else { 'Unknown' }

    $sb = New-Object System.Text.StringBuilder

    [void]$sb.AppendLine("## $stepType")
    [void]$sb.AppendLine()
    [void]$sb.AppendLine(("- **Step Name**: ``{0}``" -f $stepType))
    [void]$sb.AppendLine(("- **Implementation**: ``{0}``" -f $commandName))
    [void]$sb.AppendLine(("- **Idempotent**: ``{0}``" -f $idempotent))
    [void]$sb.AppendLine(("- **Contracts**: ``{0}``" -f $contracts))
    [void]$sb.AppendLine(("- **Events**: Unknown"))
    [void]$sb.AppendLine()
    [void]$sb.AppendLine("**Synopsis**")
    [void]$sb.AppendLine()
    [void]$sb.AppendLine($synopsis)
    [void]$sb.AppendLine()

    if (-not [string]::IsNullOrWhiteSpace($description)) {
        [void]$sb.AppendLine("**Description**")
        [void]$sb.AppendLine()
        [void]$sb.AppendLine($description)
        [void]$sb.AppendLine()
    }

    [void]$sb.AppendLine("**Inputs (With.\*)**")
    [void]$sb.AppendLine()

    if ($requiredWithKeys.Count -eq 0) {
        [void]$sb.AppendLine('_Unknown (not detected automatically). Document required With.* keys in the step help and/or use a supported pattern._')
    }
    else {
        [void]$sb.AppendLine('| Key | Required |')
        [void]$sb.AppendLine('| --- | --- |')
        foreach ($k in $requiredWithKeys) {
            [void]$sb.AppendLine("| $k | Yes |")
        }
    }

    return $sb.ToString()
}

# Resolve defaults relative to this script.
$repoRoot = Split-Path -Path $PSScriptRoot -Parent

if (-not $PSBoundParameters.ContainsKey('ModuleManifestPath')) {
    $ModuleManifestPath = Join-Path -Path $repoRoot -ChildPath 'src/IdLE/IdLE.psd1'
}
if (-not $PSBoundParameters.ContainsKey('OutputPath')) {
    $OutputPath = Join-Path -Path $repoRoot -ChildPath 'docs/reference/steps.md'
}

$ModuleManifestPath = Resolve-IdleRepoPath -Path $ModuleManifestPath

# Ensure output directory exists.
$outDir = Split-Path -Path $OutputPath -Parent
if (-not (Test-Path -Path $outDir)) {
    New-Item -Path $outDir -ItemType Directory -Force | Out-Null
}

# Import IdLE from working tree.
Remove-Module -Name 'IdLE*' -Force -ErrorAction SilentlyContinue
# Ensure step modules are loaded (Import-Module by name does NOT load nested step modules automatically).
foreach ($m in $StepModules) {
    if (Get-Module -Name $m) {
        continue
    }

    Write-Verbose "Importing step module: $m"

    try {
        # Try by module name first (works if it is already discoverable in PSModulePath).
        Import-Module -Name $m -Force -ErrorAction Stop
        continue
    }
    catch {
        # Fall back to repo-local module path pattern: ./src/<ModuleName>/<ModuleName>.psd1|psm1
        $candidatePsd1 = Join-Path -Path $repoRoot -ChildPath ("src/{0}/{0}.psd1" -f $m)
        $candidatePsm1 = Join-Path -Path $repoRoot -ChildPath ("src/{0}/{0}.psm1" -f $m)

        if (Test-Path -Path $candidatePsd1) {
            Import-Module -Name $candidatePsd1 -Force -ErrorAction Stop
            continue
        }

        if (Test-Path -Path $candidatePsm1) {
            Import-Module -Name $candidatePsm1 -Force -ErrorAction Stop
            continue
        }

        throw "Step module '$m' could not be imported. Tried module name and repo paths: '$candidatePsd1', '$candidatePsm1'."
    }
}

# Discover step commands from the configured step modules.
$stepCommands = foreach ($m in $StepModules) {
    Get-Command -Module $m -CommandType Function -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like 'Invoke-IdleStep*' }
}

$stepCommands = $stepCommands |
    Where-Object { $_.Name -and $_.Name -notin $ExcludeCommands } |
    Sort-Object -Property Name -Unique

if (-not $stepCommands) {
    throw "No step commands found. Ensure step modules are included in -StepModules (currently: $($StepModules -join ', '))."
}

$header = @(
    '# Step Catalog'
    ''
    '> Generated file. Do not edit by hand.'
    "> Source: tools/Generate-IdleStepReference.ps1"
    ''
    'This page documents built-in IdLE steps discovered from `Invoke-IdleStep*` functions in `IdLE.Steps.*` modules.'
    ''
    '---'
    ''
) -join "`n"

$body = New-Object System.Text.StringBuilder
[void]$body.AppendLine($header)

foreach ($cmd in ($stepCommands | Sort-Object)) {
    $section = ConvertTo-IdleStepMarkdownSection -CommandInfo $cmd
    if (-not [string]::IsNullOrWhiteSpace($section)) {
        [void]$body.AppendLine($section)
        [void]$body.AppendLine('---')
        [void]$body.AppendLine()
    }
}

# Normalize output:
# - remove trailing whitespace/newlines introduced by StringBuilder
# - enforce exactly one LF at EOF (avoids "one newline too many" / dangling blank line issues)
$content = ($body.ToString().TrimEnd()) + "`n"

Set-Content -Path $OutputPath -Value $content -Encoding utf8 -NoNewline

$generatedFile = Get-Item -Path $OutputPath
"Generated step reference: $($generatedFile.FullName) ($($generatedFile.Length) bytes)"

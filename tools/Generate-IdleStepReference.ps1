[CmdletBinding()]
param(
    # Path to the IdLE module manifest to import for documentation generation.
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string] $ModuleManifestPath,

    # Markdown output path for the generated index page (will be created/overwritten).
    # Example: ./docs/reference/steps.md
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string] $OutputPath,

    # Output directory for generated per-step-type pages.
    # If omitted, it is derived from OutputPath: "<parent>/steps".
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string] $DetailOutputDirectory,

    # Restrict which step modules are scanned.
    # If not specified, auto-discovers all IdLE.Steps.* modules in the repository.
    [Parameter()]

    [string[]] $StepModules,

    # Optional: Step function names to exclude (exact command names).
    [Parameter()]
    [string[]] $ExcludeCommands = @(),

    # If specified, remove previously generated per-step-type pages that no longer exist.
    # Safety: only deletes files that contain the generator marker string.
    [Parameter()]
    [switch] $CleanObsoleteDetailPages
)

<#
.SYNOPSIS
Generates Markdown reference documentation for IdLE step types.

.DESCRIPTION
This script imports the IdLE modules from the current repository clone and generates:

- An index page at -OutputPath (default: ./docs/reference/steps.md)
- One page per step type in -DetailOutputDirectory (default: ./docs/reference/steps/)

Step types are discovered from functions following the naming convention:
Invoke-IdleStep<StepType>.

The generator uses comment-based help (Get-Help) as the primary source and adds a small amount of
heuristic extraction from the step source file (e.g., required With.* keys when they are defined
in a simple static pattern).

Important:
- Do not edit generated files by hand. Update step help/source and regenerate.
- Per-step-type filenames are slugified from the StepType (kebab-case) and do not include an "idle" prefix.
  Example: "EnsureAttribute" -> "step-ensure-attribute.md"

MDX compatibility:
- Step help text may contain angle tokens like <identifier> which MDX can interpret as JSX.
- Step help text may contain braces like @{ ... } or {Name} which MDX can interpret as expressions.
- This generator sanitizes help-derived text to be MDX-safe.

Markdown linting:
- Many linters require a blank line before lists. The generator ensures there is an empty line before
  markdown list items like "- ", "* ", "+ ", or "1. ".

.PARAMETER ModuleManifestPath
Path to the IdLE module manifest (IdLE.psd1). Defaults to ./src/IdLE/IdLE.psd1 relative to this script.

.PARAMETER OutputPath
Path to the generated Markdown index page. Defaults to ./docs/reference/steps.md relative to this script.

.PARAMETER DetailOutputDirectory
Directory for generated per-step-type pages. Defaults to "<parent of OutputPath>/steps".

.PARAMETER StepModules
Modules that contain step functions (IdLE.Steps.*). 
If not specified, automatically discovers all IdLE.Steps.* modules in the src/ directory.

.PARAMETER ExcludeCommands
Specific step function names to exclude (exact command names).

.PARAMETER CleanObsoleteDetailPages
If specified, delete previously generated detail pages that are no longer produced.

.EXAMPLE
pwsh ./tools/Generate-IdleStepReference.ps1

.OUTPUTS
System.String
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:GeneratorMarker = 'Source: tools/Generate-IdleStepReference.ps1'

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

function Ensure-IdleBlankLineBeforeMarkdownLists {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text
    )

    # Many markdown linters require a blank line before lists.
    # Also applies to: "* ", "+ ", and numbered lists "1. ".
    $t = $Text -replace "`r`n", "`n" -replace "`r", "`n"

    $t = [regex]::Replace(
        $t,
        '(?m)(?<=\S)\n(?=(?:- |\* |\+ |\d+\. ))',
        "`n`n"
    )

    return $t
}

function ConvertTo-IdleMdxSafeText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text
    )

    # NOTE:
    # We intentionally sanitize ONLY help-derived text (synopsis/description),
    # not the full generated Markdown structure.

    $t = $Text -replace "`r`n", "`n" -replace "`r", "`n"

    # Replace <token> with HTML entities (MDX/JSX safety).
    $t = $t -replace '<(?<tok>[A-Za-z][A-Za-z0-9_-]*)>', '&lt;${tok}&gt;'

    # Escape braces to avoid MDX expression parsing, e.g. @{ ... } or {Name}.
    $t = $t -replace '\{', '\{'
    $t = $t -replace '\}', '\}'

    # Lint-friendly markdown lists.
    $t = Ensure-IdleBlankLineBeforeMarkdownLists -Text $t

    return $t.Trim()
}

function Get-IdleStepTypeFromCommandName {
    <#
    .SYNOPSIS
    Resolves the canonical step type(s) for a command by loading and inverting the step registry.
    
    .DESCRIPTION
    Instead of deriving step types from command names (which can be ambiguous),
    this function loads the step registry script and inverts it to find the actual
    registered step type(s).
    
    .PARAMETER CommandName
    The step handler command name (e.g., 'Invoke-IdleStepMailboxOutOfOfficeEnsure').
    
    .OUTPUTS
    Array of step type strings registered for this command, or empty array if not found.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $CommandName
    )

    # Load the step registry script to access its mappings
    $registryPath = Join-Path $script:repoRoot 'src' 'IdLE.Core' 'Private' 'Get-IdleStepRegistry.ps1'
    
    if (-not (Test-Path $registryPath)) {
        Write-Warning "Step registry not found at: $registryPath"
        return @()
    }

    # Read the registry file and extract step type → handler mappings
    $registryContent = Get-Content -Path $registryPath -Raw
    
    # Scan for command name and find nearby step type
    $lines = $registryContent -split "`n"
    $stepTypes = @()
    
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match "CommandName\s+'$([regex]::Escape($CommandName))'") {
            # Look backwards for the step type in the ContainsKey check
            for ($j = $i; $j -ge [Math]::Max(0, $i - 10); $j--) {
                if ($lines[$j] -match "ContainsKey\('([^']+)'\)") {
                    $stepType = $matches[1]
                    if ($stepType -and $stepType -notlike '*$*') {
                        $stepTypes += $stepType
                        break
                    }
                }
            }
        }
    }
    
    return $stepTypes | Select-Object -Unique
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
    # OR throw messages like: "StepName requires With.KeyName."
    $filePath = $null
    if ($CommandInfo.ScriptBlock -and $CommandInfo.ScriptBlock.File) {
        $filePath = $CommandInfo.ScriptBlock.File
    }

    if ([string]::IsNullOrWhiteSpace($filePath) -or -not (Test-Path -Path $filePath)) {
        return @()
    }

    $content = Get-Content -Path $filePath -Raw -ErrorAction Stop
    $keys = @()

    # Pattern 1: foreach loop with key array
    $m = [regex]::Match(
        $content,
        'foreach\s*\(\s*\$key\s+in\s+@\((?<List>[^)]*)\)\s*\)',
        'IgnoreCase'
    )

    if ($m.Success) {
        $listText = $m.Groups['List'].Value
        $foreachKeys = [regex]::Matches($listText, "'(?<Key>[^']+)'") | ForEach-Object { $_.Groups['Key'].Value }
        $keys += $foreachKeys
    }

    # Pattern 2: throw messages like "requires With.KeyName"
    $throwMatches = [regex]::Matches(
        $content,
        'throw\s+[^"]*"[^"]*requires\s+With\.(?<Key>[A-Za-z][A-Za-z0-9]*)',
        'IgnoreCase'
    )
    foreach ($match in $throwMatches) {
        $keys += $match.Groups['Key'].Value
    }

    # Pattern 3: ContainsKey checks followed by throw
    $containsMatches = [regex]::Matches(
        $content,
        '\$with\.ContainsKey\(''(?<Key>[^'']+)''\)',
        'IgnoreCase'
    )
    foreach ($match in $containsMatches) {
        $keyName = $match.Groups['Key'].Value
        # Only include if there's a throw statement nearby (within next 100 chars)
        $matchPos = $match.Index
        $nextChunk = $content.Substring($matchPos, [Math]::Min(150, $content.Length - $matchPos))
        if ($nextChunk -match 'throw') {
            $keys += $keyName
        }
    }

    return @($keys | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique | Sort-Object)
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
    $m = [regex]::Match(
        $DescriptionText,
        'must\s+implement\s+an?\s+(?<Method>[A-Za-z0-9_]+)\s+method',
        'IgnoreCase'
    )

    if (-not $m.Success) {
        return $null
    }

    return $m.Groups['Method'].Value
}

function ConvertTo-IdleKebabCase {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Text
    )

    # Robust kebab-case conversion (prevents per-letter splitting).
    #
    # 1) Split acronym-to-word boundaries: "EntraID" -> "Entra-ID"
    #    (?<=[A-Z])(?=[A-Z][a-z])
    # 2) Split lower-to-upper boundaries: "CreateIdentity" -> "Create-Identity"
    #    (?<=[a-z0-9])(?=[A-Z])
    $t = $Text

    $t = [regex]::Replace($t, '(?<=[A-Z])(?=[A-Z][a-z])', '-')
    $t = [regex]::Replace($t, '(?<=[a-z0-9])(?=[A-Z])', '-')

    # Normalize common separators to hyphen
    $t = $t -replace '[\._\s]+', '-'

    # Collapse duplicates and lowercase
    $t = $t -replace '-{2,}', '-'
    $t = $t.Trim('-').ToLowerInvariant()

    return $t
}

function ConvertTo-IdleStepSlug {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $StepType
    )

    $slug = ConvertTo-IdleKebabCase -Text $StepType

    # Remove optional IdLE-related prefixes (user-facing file names should not include "idle").
    # Handle both kebab-case (id-le-step-) and lowercase (idle-step-) prefixes
    $slug = $slug -replace '^id-le-step-', ''
    $slug = $slug -replace '^idle-step-', ''
    $slug = $slug -replace '^id-le-', ''
    $slug = $slug -replace '^idle-', ''

    # Ensure the file name remains self-explanatory.
    if (-not $slug.StartsWith('step-')) {
        $slug = "step-$slug"
    }

    if ([string]::IsNullOrWhiteSpace($slug)) {
        throw "Failed to derive a slug for step type: '$StepType'."
    }

    return $slug
}

function Get-IdleCommandModuleName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [System.Management.Automation.CommandInfo] $CommandInfo
    )

    # Prefer ModuleName (string), then Module.Name, else Unknown.
    $moduleName = $CommandInfo.ModuleName
    if (-not [string]::IsNullOrWhiteSpace($moduleName)) {
        return $moduleName
    }

    if ($null -ne $CommandInfo.Module -and -not [string]::IsNullOrWhiteSpace($CommandInfo.Module.Name)) {
        return $CommandInfo.Module.Name
    }

    return 'Unknown'
}

function Get-IdleStepRequiredCapabilities {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $StepType,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $ModuleName
    )

    # Try to load metadata catalog from the step's module to get required capabilities
    try {
        # Disambiguate in case multiple versions of the module are loaded
        $module = Get-Module -Name $ModuleName -All -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -ne $module) {
            # Call Get-IdleStepMetadataCatalog in the context of the specific module
            $catalog = & $module { Get-IdleStepMetadataCatalog -ErrorAction SilentlyContinue }
            if ($catalog -is [System.Collections.IDictionary]) {
                $fullStepTypeName = "IdLE.Step.$StepType"
                if ($catalog.Contains($fullStepTypeName)) {
                    $metadata = $catalog[$fullStepTypeName]
                    if ($metadata) {
                        $requiredCapabilities = $null
                        if ($metadata -is [System.Collections.IDictionary] -and $metadata.Contains('RequiredCapabilities')) {
                            $requiredCapabilities = $metadata['RequiredCapabilities']
                        }
                        elseif ($metadata.PSObject -and $metadata.PSObject.Properties['RequiredCapabilities']) {
                            $requiredCapabilities = $metadata.RequiredCapabilities
                        }

                        if ($null -ne $requiredCapabilities) {
                            return @($requiredCapabilities)
                        }
                    }
                }
            }
        }
    }
    catch {
        # Metadata catalog not available or error loading it
    }

    return @()
}

function Get-IdleWithKeyMetadata {
    <#
    .SYNOPSIS
    Returns type, required, default, and description metadata for a well-known With.* key.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Key
    )

    switch ($Key) {
        'IdentityKey' {
            return [pscustomobject]@{
                Type        = 'string'
                Required    = 'Yes'
                Default     = '—'
                Description = 'UPN, SMTP address, or other identity key recognized by the provider. Supports ``\{\{Request.*\}\}`` template expressions.'
            }
        }
        'Provider' {
            return [pscustomobject]@{
                Type        = 'string'
                Required    = 'No'
                Default     = 'Step-specific'
                Description = 'Provider alias key in the providers map supplied at runtime.'
            }
        }
        'AuthSessionName' {
            return [pscustomobject]@{
                Type        = 'string'
                Required    = 'No'
                Default     = '``Provider`` value'
                Description = 'Auth session name passed to ``Context.AcquireAuthSession()``. Defaults to the ``Provider`` value.'
            }
        }
        'AuthSessionOptions' {
            return [pscustomobject]@{
                Type        = 'hashtable'
                Required    = 'No'
                Default     = '``$null``'
                Description = 'Data-only options passed to the auth session broker (e.g., ``@\{ Role = ''Admin'' \}``). ScriptBlocks are rejected.'
            }
        }
        'Permissions' {
            return [pscustomobject]@{
                Type        = 'hashtable[]'
                Required    = 'Yes'
                Default     = '—'
                Description = 'Array of permission entries. Each entry requires: ``AssignedUser`` (string — UPN/SMTP), ``Right`` (``FullAccess``\|``SendAs``\|``SendOnBehalf``), ``Ensure`` (``Present``\|``Absent``).'
            }
        }
        'Config' {
            return [pscustomobject]@{
                Type        = 'hashtable'
                Required    = 'Yes'
                Default     = '—'
                Description = 'Configuration hashtable for the operation. See the Description section for the full property schema.'
            }
        }
        'MailboxType' {
            return [pscustomobject]@{
                Type        = 'string'
                Required    = 'Yes'
                Default     = '—'
                Description = 'Desired mailbox type: ``User`` \| ``Shared`` \| ``Room`` \| ``Equipment``.'
            }
        }
        'Attributes' {
            return [pscustomobject]@{
                Type        = 'hashtable'
                Required    = 'Yes'
                Default     = '—'
                Description = 'Hashtable of attribute name → desired value pairs to converge on the identity.'
            }
        }
        'Entitlement' {
            return [pscustomobject]@{
                Type        = 'hashtable'
                Required    = 'Yes'
                Default     = '—'
                Description = 'Entitlement descriptor: ``Kind`` (string), ``Id`` (string), optional ``DisplayName`` (string).'
            }
        }
        'State' {
            return [pscustomobject]@{
                Type        = 'string'
                Required    = 'Yes'
                Default     = '—'
                Description = 'Desired assignment state: ``Present`` \| ``Absent``.'
            }
        }
        'Message' {
            return [pscustomobject]@{
                Type        = 'string'
                Required    = 'No'
                Default     = '—'
                Description = 'Custom message text to emit in the event.'
            }
        }
        'DestinationPath' {
            return [pscustomobject]@{
                Type        = 'string'
                Required    = 'Yes'
                Default     = '—'
                Description = 'Target location or path (e.g., OU distinguished name for AD moves).'
            }
        }
        'PolicyType' {
            return [pscustomobject]@{
                Type        = 'string'
                Required    = 'No'
                Default     = '``Delta``'
                Description = 'Sync policy type: ``Delta`` \| ``Initial``.'
            }
        }
        'Wait' {
            return [pscustomobject]@{
                Type        = 'bool'
                Required    = 'No'
                Default     = '``$false``'
                Description = 'Whether to wait for the sync operation to complete before continuing.'
            }
        }
        default {
            return [pscustomobject]@{
                Type        = 'string'
                Required    = 'Yes'
                Default     = '—'
                Description = 'See step description for details.'
            }
        }
    }
}

function Get-IdleExamplesFromHelp {
    <#
    .SYNOPSIS
    Extracts the .EXAMPLE blocks from a Get-Help result and returns structured objects.

    .OUTPUTS
    Array of PSCustomObjects with Code and Title properties.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object] $Help
    )

    if ($null -eq $Help) {
        return @()
    }

    # Get-Help returns Examples differently depending on version/context.
    # Try both $help.examples.example and $help.Examples.Example.
    $exampleObjects = $null
    try {
        if ($Help.PSObject.Properties.Name -contains 'examples' -and
            $null -ne $Help.examples -and
            $null -ne $Help.examples.example) {
            $exampleObjects = $Help.examples.example
        }
        elseif ($Help.PSObject.Properties.Name -contains 'Examples' -and
            $null -ne $Help.Examples -and
            $null -ne $Help.Examples.Example) {
            $exampleObjects = $Help.Examples.Example
        }
    }
    catch {
        return @()
    }

    if ($null -eq $exampleObjects) {
        return @()
    }

    $results = New-Object System.Collections.Generic.List[pscustomobject]

    foreach ($ex in $exampleObjects) {
        $rawCode = ''
        try {
            if ($ex.PSObject.Properties.Name -contains 'Code' -and $null -ne $ex.Code) {
                $rawCode = ($ex.Code | Out-String).Trim()
            }
        }
        catch {
            continue
        }

        if ([string]::IsNullOrWhiteSpace($rawCode)) {
            continue
        }

        # If Code only has comment lines (no executable code), try to append Remarks.
        # The PS help parser splits .EXAMPLE at the first blank line; the @{...} block
        # often ends up in Remarks for multi-section examples.
        $hasExecutableLine = @($rawCode -split "`n" | Where-Object { $_.Trim() -and -not $_.Trim().StartsWith('#') }).Count -gt 0
        if (-not $hasExecutableLine) {
            $remarksText = ''
            try {
                $remarksRaw = $null
                if ($ex.PSObject.Properties.Name -contains 'remarks') { $remarksRaw = $ex.remarks }
                elseif ($ex.PSObject.Properties.Name -contains 'Remarks') { $remarksRaw = $ex.Remarks }

                if ($null -ne $remarksRaw) {
                    $texts = New-Object System.Collections.Generic.List[string]
                    foreach ($r in @($remarksRaw)) {
                        if ($null -eq $r) { continue }
                        if ($r -is [string]) {
                            if (-not [string]::IsNullOrWhiteSpace($r)) { $texts.Add($r) }
                        }
                        elseif ($r.PSObject.Properties.Name -contains 'Text' -and
                                -not [string]::IsNullOrWhiteSpace([string]$r.Text)) {
                            $texts.Add([string]$r.Text)
                        }
                    }
                    $remarksText = ($texts -join "`n").Trim()
                }
            }
            catch {}

            if (-not [string]::IsNullOrWhiteSpace($remarksText)) {
                $rawCode = "$rawCode`n`n$remarksText"
            }
            else {
                # Skip examples that are only comments with no associated code
                continue
            }
        }

        # Try to extract a title from the first comment line in the code block.
        $title = ''
        $firstLine = ($rawCode -split "`n")[0].Trim()
        if ($firstLine -match '^#\s*(.+)') {
            $title = $matches[1].TrimEnd(':').Trim()
        }

        $results.Add([pscustomobject]@{
            Code  = $rawCode
            Title = $title
        })
    }

    return $results.ToArray()
}

function New-IdleStepDocModel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [System.Management.Automation.CommandInfo] $CommandInfo
    )

    $commandName = $CommandInfo.Name
    $stepTypes = @(Get-IdleStepTypeFromCommandName -CommandName $commandName)
    
    if ($stepTypes.Count -eq 0) {
        Write-Warning "No step types found in registry for command: $commandName"
        return $null
    }

    # Use the first (or only) step type as the primary
    $stepType = $stepTypes[0]

    $moduleName = Get-IdleCommandModuleName -CommandInfo $CommandInfo
    $help = Get-IdleHelpSafe -CommandName $commandName

    $synopsis = ''
    $description = ''

    if ($null -ne $help) {
        if ($help.Synopsis) {
            $synopsis = ConvertTo-IdleMarkdownSafeText -Text ($help.Synopsis | Out-String)
            $synopsis = ConvertTo-IdleMdxSafeText -Text $synopsis
        }
        if ($help.Description -and $help.Description.Text) {
            $description = ConvertTo-IdleMarkdownSafeText -Text (($help.Description.Text -join "`n") | Out-String)
            $description = ConvertTo-IdleMdxSafeText -Text $description
        }
    }

    if ([string]::IsNullOrWhiteSpace($synopsis)) {
        $synopsis = 'No synopsis available (missing comment-based help).'
    }

    # Remove redundant "This is a provider-agnostic step." sentence
    $description = $description -replace '(?i)This\s+is\s+a\s+provider-agnostic\s+step\.\s*', ''

    $requiredWithKeys = @(Get-IdleRequiredWithKeysFromSource -CommandInfo $CommandInfo)

    $idempotent = 'Unknown'
    if ($description -match '(?i)\bidempotent\b') {
        $idempotent = 'Yes'
    }

    # Get required capabilities from metadata catalog (use primary step type)
    $requiredCapabilities = @(Get-IdleStepRequiredCapabilities -StepType $stepType -ModuleName $moduleName)

    # Extract examples from help (.EXAMPLE blocks)
    $examples = @(Get-IdleExamplesFromHelp -Help $help)

    $slug = ConvertTo-IdleStepSlug -StepType $stepType

    return [pscustomobject]@{
        StepType              = $stepType
        Slug                  = $slug
        ModuleName            = $moduleName
        CommandName           = $commandName
        Synopsis              = $synopsis
        Description           = $description
        RequiredWithKeys      = $requiredWithKeys
        Idempotent            = $idempotent
        RequiredCapabilities  = $requiredCapabilities
        Examples              = $examples
    }
}

function New-IdleStepDetailPageContent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [pscustomobject] $Model
    )

    $sb = New-Object System.Text.StringBuilder

    [void]$sb.AppendLine("# $($Model.StepType)")
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('> Generated file. Do not edit by hand.')
    [void]$sb.AppendLine("> $script:GeneratorMarker")
    [void]$sb.AppendLine()

    [void]$sb.AppendLine('## Summary')
    [void]$sb.AppendLine()
    [void]$sb.AppendLine(("- **Step Type**: ``{0}``" -f $Model.StepType))
    [void]$sb.AppendLine(("- **Module**: ``{0}``" -f $Model.ModuleName))
    [void]$sb.AppendLine(("- **Implementation**: ``{0}``" -f $Model.CommandName))
    [void]$sb.AppendLine(("- **Idempotent**: ``{0}``" -f $Model.Idempotent))
    
    # Only show Required Capabilities if we have any
    if ($Model.RequiredCapabilities -and $Model.RequiredCapabilities.Count -gt 0) {
        $capsFormatted = ($Model.RequiredCapabilities | ForEach-Object { "``$_``" }) -join ', '
        [void]$sb.AppendLine(("- **Required Capabilities**: {0}" -f $capsFormatted))
    }
    [void]$sb.AppendLine()

    [void]$sb.AppendLine('## Synopsis')
    [void]$sb.AppendLine()
    [void]$sb.AppendLine($Model.Synopsis.Trim())
    [void]$sb.AppendLine()

    if (-not [string]::IsNullOrWhiteSpace($Model.Description)) {
        [void]$sb.AppendLine('## Description')
        [void]$sb.AppendLine()
        [void]$sb.AppendLine($Model.Description.Trim())
        [void]$sb.AppendLine()
    }

    [void]$sb.AppendLine('## Inputs (With.*)')
    [void]$sb.AppendLine()

    # Detect whether this is a provider-backed step (uses AuthSession / Provider pattern)
    $isProviderStep = ($Model.Description -match 'AuthSession|AuthSessionName|Provider|Context\.Providers')

    if ($Model.RequiredWithKeys.Count -eq 0) {
        [void]$sb.AppendLine('The required input keys could not be detected automatically.')
        [void]$sb.AppendLine('Please refer to the step description and examples for usage details.')
        [void]$sb.AppendLine()
    }
    else {
        [void]$sb.AppendLine('The following keys are supported in the step''s ``With`` configuration:')
        [void]$sb.AppendLine()
        [void]$sb.AppendLine('| Key | Type | Required | Default | Description |')
        [void]$sb.AppendLine('| --- | --- | --- | --- | --- |')

        foreach ($k in $Model.RequiredWithKeys) {
            $meta = Get-IdleWithKeyMetadata -Key $k
            # Keys detected in RequiredWithKeys are always required, regardless of default metadata.
            [void]$sb.AppendLine("| ``$k`` | ``$($meta.Type)`` | Yes | $($meta.Default) | $($meta.Description) |")
        }

        # Append standard optional provider/auth keys for provider-backed steps,
        # unless they were already listed as required keys.
        if ($isProviderStep) {
            $alreadyListed = @($Model.RequiredWithKeys)
            $optionalStdKeys = @('Provider', 'AuthSessionName', 'AuthSessionOptions') |
                Where-Object { $_ -notin $alreadyListed }
            foreach ($k in $optionalStdKeys) {
                $meta = Get-IdleWithKeyMetadata -Key $k
                [void]$sb.AppendLine("| ``$k`` | ``$($meta.Type)`` | $($meta.Required) | $($meta.Default) | $($meta.Description) |")
            }
        }

        [void]$sb.AppendLine()
    }

    # Examples section — prefer real .EXAMPLE blocks from help over the auto-generated stub.
    if ($Model.Examples -and $Model.Examples.Count -gt 0) {
        [void]$sb.AppendLine('## Examples')
        [void]$sb.AppendLine()

        for ($i = 0; $i -lt $Model.Examples.Count; $i++) {
            $ex = $Model.Examples[$i]

            if (-not [string]::IsNullOrWhiteSpace($ex.Title)) {
                [void]$sb.AppendLine("### Example $($i + 1) — $($ex.Title)")
            }
            else {
                [void]$sb.AppendLine("### Example $($i + 1)")
            }
            [void]$sb.AppendLine()
            [void]$sb.AppendLine('```powershell')
            [void]$sb.AppendLine($ex.Code)
            [void]$sb.AppendLine('```')
            [void]$sb.AppendLine()
        }
    }
    else {
        # Fallback: auto-generate a minimal example from required keys.
        [void]$sb.AppendLine('## Example')
        [void]$sb.AppendLine()
        [void]$sb.AppendLine('```powershell')
        [void]$sb.AppendLine('@{')
        [void]$sb.AppendLine(("  Name = '{0} Example'" -f $Model.StepType))
        [void]$sb.AppendLine(("  Type = '{0}'" -f $Model.StepType))
        [void]$sb.AppendLine('  With = @{')

        if ($Model.RequiredWithKeys.Count -gt 0) {
            foreach ($k in $Model.RequiredWithKeys) {
                $exampleValue = switch ($k) {
                    'IdentityKey'      { '''user@contoso.com''' }
                    'Name'             { '''AttributeName''' }
                    'Value'            { '''AttributeValue''' }
                    'Attributes'       { "@{ GivenName = 'First'; Surname = 'Last' }" }
                    'DestinationPath'  { '''OU=Users,DC=domain,DC=com''' }
                    'Message'          { '''Custom event message''' }
                    'EntitlementType'  { '''Group''' }
                    'EntitlementValue' { '''CN=GroupName,OU=Groups,DC=domain,DC=com''' }
                    'Entitlement'      { "@{ Kind = 'Group'; Id = 'GroupId'; DisplayName = 'Example Group' }" }
                    'State'            { '''Present''' }
                    'Ensure'           { '''Present''' }
                    'Provider'         { '''Identity''' }
                    'AuthSessionName'  { '''AdminSession''' }
                    'PolicyType'       { '''Delta''' }
                    'Wait'             { '$true' }
                    default            { '''<value>''' }
                }
                [void]$sb.AppendLine(("    {0,-20} = {1}" -f $k, $exampleValue))
            }
        }
        else {
            [void]$sb.AppendLine('    # See step description for available options')
        }

        [void]$sb.AppendLine('  }')
        [void]$sb.AppendLine('}')
        [void]$sb.AppendLine('```')
        [void]$sb.AppendLine()
    }

    # Add "See Also" section for consistency across all step pages
    [void]$sb.AppendLine('## See Also')
    [void]$sb.AppendLine()
    if ($Model.RequiredCapabilities -and $Model.RequiredCapabilities.Count -gt 0) {
        [void]$sb.AppendLine('- [Capabilities Reference](../capabilities.md) - Details on required capabilities')
    }
    else {
        [void]$sb.AppendLine('- [Capabilities Reference](../capabilities.md) - Overview of IdLE capabilities')
    }
    [void]$sb.AppendLine('- [Providers](../providers.md) - Available provider implementations')
    [void]$sb.AppendLine()

    # Normalize output: ensure exactly one LF at EOF.
    return ($sb.ToString().TrimEnd()) + "`n"
}

function New-IdleStepsIndexPageContent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [pscustomobject[]] $Models
    )

    $sb = New-Object System.Text.StringBuilder

    [void]$sb.AppendLine('# Steps')
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('> Generated file. Do not edit by hand.')
    [void]$sb.AppendLine("> $script:GeneratorMarker")
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('| Step Type | Module | Synopsis |')
    [void]$sb.AppendLine('| --- | --- | --- |')

    foreach ($m in ($Models | Sort-Object -Property StepType)) {
        # Keep synopsis a single line in the table.
        $syn = ($m.Synopsis -replace '\s+', ' ').Trim()
        [void]$sb.AppendLine(('| [{0}](steps/{1}.md) | ``{2}`` | {3} |' -f $m.StepType, $m.Slug, $m.ModuleName, $syn))
    }

    return ($sb.ToString().TrimEnd()) + "`n"
}

function Remove-IdleObsoleteGeneratedPages {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Directory,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [string[]] $KeepFileNames
    )

    if (-not (Test-Path -Path $Directory)) {
        return
    }

    $keep = @{}
    foreach ($k in $KeepFileNames) { $keep[$k] = $true }

    Get-ChildItem -Path $Directory -Filter '*.md' -File -ErrorAction SilentlyContinue | ForEach-Object {
        if ($keep.ContainsKey($_.Name)) {
            return
        }

        # Safety: only delete if it is clearly generated by this script.
        $text = Get-Content -Path $_.FullName -Raw -ErrorAction SilentlyContinue
        if ($null -ne $text -and $text -like "*$script:GeneratorMarker*") {
            Remove-Item -Path $_.FullName -Force -ErrorAction Stop
        }
    }
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

if (-not $PSBoundParameters.ContainsKey('DetailOutputDirectory') -or [string]::IsNullOrWhiteSpace($DetailOutputDirectory)) {
    $DetailOutputDirectory = Join-Path -Path $outDir -ChildPath 'steps'
}

if (-not (Test-Path -Path $DetailOutputDirectory)) {
    New-Item -Path $DetailOutputDirectory -ItemType Directory -Force | Out-Null
}

# Import IdLE from working tree.
Remove-Module -Name 'IdLE*' -Force -ErrorAction SilentlyContinue
Import-Module -Name $ModuleManifestPath -Force -ErrorAction Stop

# Auto-discover step modules if not specified
if (-not $StepModules -or $StepModules.Count -eq 0) {
    Write-Verbose "Auto-discovering step modules in repository..."
    
    $srcPath = Join-Path -Path $repoRoot -ChildPath 'src'
    $stepModuleDirs = Get-ChildItem -Path $srcPath -Directory -Filter 'IdLE.Steps.*' -ErrorAction SilentlyContinue
    
    if ($stepModuleDirs) {
        $StepModules = @($stepModuleDirs | Select-Object -ExpandProperty Name | Sort-Object)
        Write-Verbose "Discovered step modules: $($StepModules -join ', ')"
    }
    else {
        Write-Warning "No IdLE.Steps.* modules found in '$srcPath'. Using empty module list."
        $StepModules = @()
    }
}

# Ensure step modules are loaded (Import-Module IdLE.psd1 does NOT load nested step modules automatically).
# Always prefer repo-local modules to avoid importing different versions from PSModulePath.
foreach ($m in $StepModules) {
    if (Get-Module -Name $m) {
        # Check if the loaded module is from the repo (not PSModulePath)
        $loadedModule = Get-Module -Name $m
        
        # Normalize paths for case-insensitive comparison (Windows compatibility)
        $loadedModuleBase = if ($loadedModule.ModuleBase) {
            [System.IO.Path]::GetFullPath($loadedModule.ModuleBase)
        } else { '' }
        $repoRootNormalized = [System.IO.Path]::GetFullPath($repoRoot)
        
        $isRepoModule = $loadedModuleBase -and 
                        $loadedModuleBase.StartsWith($repoRootNormalized, [System.StringComparison]::OrdinalIgnoreCase)
        
        if ($isRepoModule) {
            Write-Verbose "Step module '$m' already loaded from repo: $($loadedModule.ModuleBase)"
            continue
        }
        else {
            Write-Verbose "Removing non-repo version of '$m' from: $($loadedModule.ModuleBase)"
            Remove-Module -Name $m -Force -ErrorAction SilentlyContinue
        }
    }

    Write-Verbose "Importing step module: $m"

    # Try repo-local module path first (prioritize over PSModulePath)
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

    # Fall back to module name (PSModulePath) only if repo-local not found
    try {
        Import-Module -Name $m -Force -ErrorAction Stop
    }
    catch {
        throw "Step module '$m' could not be imported. Tried repo paths: '$candidatePsd1', '$candidatePsm1'."
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

# Build documentation models.
$models = foreach ($cmd in $stepCommands) {
    New-IdleStepDocModel -CommandInfo $cmd
}

$models = @($models | Where-Object { $null -ne $_ } | Sort-Object -Property StepType)

if ($models.Count -eq 0) {
    throw "No step documentation models produced. Ensure step functions match 'Invoke-IdleStep<StepType>'."
}

# Write per-step-type pages.
$generatedDetailNames = New-Object System.Collections.Generic.List[string]

foreach ($m in $models) {
    $fileName = "$($m.Slug).md"
    $filePath = Join-Path -Path $DetailOutputDirectory -ChildPath $fileName

    $pageContent = New-IdleStepDetailPageContent -Model $m
    Set-Content -Path $filePath -Value $pageContent -Encoding utf8 -NoNewline

    $generatedDetailNames.Add($fileName) | Out-Null
}

# Optionally remove obsolete generated pages.
if ($CleanObsoleteDetailPages) {
    Remove-IdleObsoleteGeneratedPages -Directory $DetailOutputDirectory -KeepFileNames $generatedDetailNames.ToArray()
}

# Write index page.
$indexContent = New-IdleStepsIndexPageContent -Models $models
Set-Content -Path $OutputPath -Value $indexContent -Encoding utf8 -NoNewline

$generatedFile = Get-Item -Path $OutputPath
"Generated`n`tStep reference index: $($generatedFile.FullName) ($($generatedFile.Length) bytes)`n`tDetail pages: $($models.Count) in '$DetailOutputDirectory'"

#requires -PSEdition Core
#requires -Version 7.0

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string] $DocsPath = ".\docs",

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string] $WebsitePath = ".\website",

    [Parameter()]
    [ValidateRange(50, 5000)]
    [int] $LongPageLineThreshold = 350,

    # Additional exclude patterns (glob) for docs files, in addition to docusaurus.config.js docs.exclude.
    # Examples:
    # - '**/develop/**'
    # - '**/_TO-SORT_/**'
    [Parameter()]
    [string[]] $AdditionalExcludeGlobs = @(),

    # If specified, also audit excluded docs (still will not count as orphans).
    [Parameter()]
    [switch] $IncludeExcludedDocs,

    # CI behavior: fail build when issues are found.
    [Parameter()]
    [switch] $FailOnOrphans = $true,

    [Parameter()]
    [switch] $FailOnLinkIssues = $true,

    [Parameter()]
    [switch] $FailOnMdxRisks = $true,

    # If specified, write a non-zero exit code on warnings (not recommended).
    [Parameter()]
    [switch] $FailOnLongPages = $false,

    [Parameter()]
    [ValidateRange(1, 5000)]
    [int] $MaxDetailItems = 50,

    [Parameter()]
    [switch] $NoDetailOutput,

    # Output file path for JSON report.
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string] $OutputJsonPath = "$PSScriptRoot\..\artifacts\docs-audit.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-FullPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Path
    )

    return (Resolve-Path -Path $Path).Path
}

function Convert-GlobToRegex {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Glob
    )

    # Normalize to forward slashes like minimatch does
    $g = $Glob -replace '\\', '/'

    # Docusaurus/minimatch semantics:
    # A leading "**/" should also match the root (i.e. it is optional).
    # Example: "**/develop/**" must match "develop/x.md" AND "a/develop/x.md"
    $leadingGlobStarSlash = $false
    if ($g.StartsWith('**/')) {
        $leadingGlobStarSlash = $true
        $g = $g.Substring(3) # remove "**/"
    }

    # Escape everything, then re-expand glob tokens
    $g = [regex]::Escape($g)

    # Restore glob tokens (escaped) to regex
    $g = $g -replace '\\\*\\\*', '___GLOBSTAR___'
    $g = $g -replace '\\\*', '___STAR___'
    $g = $g -replace '\\\?', '___Q___'

    $g = $g -replace '___GLOBSTAR___', '.*'
    $g = $g -replace '___STAR___', '[^/]*'
    $g = $g -replace '___Q___', '[^/]'

    if ($leadingGlobStarSlash) {
        # Optional leading path segments
        return "^(?:.*/)?$g$"
    }

    return "^$g$"
}

function Test-GlobMatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $PathLike,

        [Parameter(Mandatory)]
        [string[]] $Globs
    )

    $p = $PathLike -replace '\\', '/'
    foreach ($glob in $Globs) {
        if ([string]::IsNullOrWhiteSpace($glob)) { continue }
        $rx = Convert-GlobToRegex -Glob $glob
        if ($p -match $rx) { return $true }
    }
    return $false
}

function Get-NodePath {
    [CmdletBinding()]
    param()

    $cmd = Get-Command node -ErrorAction SilentlyContinue
    if ($null -eq $cmd) {
        throw "Node.js is required to read Docusaurus config/sidebars. Install Node.js and ensure 'node' is on PATH."
    }
    return $cmd.Source
}

function Get-DocusaurusDocsExcludeGlobs {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $WebsitePath
    )

    $node = Get-NodePath
    $configPath = Join-Path $WebsitePath "docusaurus.config.js"
    if (-not (Test-Path $configPath)) {
        return @()
    }

    # Pass the path as an argument to Node (process.argv),
    # do NOT interpolate Windows paths into JS string literals.
    $script = @"
const fs = require('fs');

const cfgPath = process.argv[1];
const text = fs.readFileSync(cfgPath, 'utf8');

// Heuristic: find "docs: { ... exclude: [ ... ] ... }"
const m = text.match(/docs\s*:\s*\{[\s\S]*?exclude\s*:\s*\[([\s\S]*?)\]/m);
if (!m) {
  console.log('[]');
  process.exit(0);
}

const arrBody = m[1];

// Extract quoted strings inside the exclude array
const globs = [];
const re = /['"`]([^'"`]+)['"`]/g;
let match;
while ((match = re.exec(arrBody)) !== null) {
  globs.push(match[1]);
}

console.log(JSON.stringify(globs));
"@

    $json = & $node -e $script $configPath
    if ([string]::IsNullOrWhiteSpace($json)) { return @() }

    try {
        $globs = $json | ConvertFrom-Json
        if ($null -eq $globs) { return @() }
        return @($globs | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }
    catch {
        throw "Failed to parse docs.exclude globs from docusaurus.config.js: $($_.Exception.Message)"
    }
}

function Get-SidebarDocIds {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $WebsitePath
    )

    $sidebarsJs = Join-Path $WebsitePath "sidebars.js"
    if (-not (Test-Path $sidebarsJs)) {
        Write-Warning "sidebars.js not found: $sidebarsJs"
        return @()
    }

    $node = Get-NodePath

    $script = @"
const path = require('path');
const sbPath = process.argv[1];
const sb = require(path.resolve(sbPath));

const ids = new Set();
function visit(n) {
  if (n == null) return;
  if (typeof n === 'string') { ids.add(n); return; }
  if (Array.isArray(n)) { for (const i of n) visit(i); return; }
  if (typeof n === 'object') { for (const k of Object.keys(n)) visit(n[k]); }
}
visit(sb);
console.log(JSON.stringify(Array.from(ids)));
"@

    $json = & $node -e $script $sidebarsJs
    if ([string]::IsNullOrWhiteSpace($json)) { return @() }

    return @(($json | ConvertFrom-Json) | Select-Object -Unique)
}

function Get-DocIdFromPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $DocsRoot,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $FilePath
    )

    $root = (Resolve-Path $DocsRoot).Path
    $full = (Resolve-Path $FilePath).Path

    $rel = $full.Substring($root.Length).TrimStart('\', '/')
    $rel = $rel -replace '\.mdx?$', ''
    return ($rel -replace '\\', '/')
}

function Get-MarkdownLinks {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Content
    )

    # matches [text](target) ignoring images ![...](...)
    $pattern = '(?<!!)\[[^\]]*\]\((?<t>[^)]+)\)'
    return [regex]::Matches($Content, $pattern) | ForEach-Object { $_.Groups['t'].Value }
}

function Test-InternalLinkTarget {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $DocsRoot,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $FromFile,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Target
    )

    # ignore external
    if ($Target -match '^(https?:)?//') { return $null }
    if ($Target -match '^(mailto:|tel:)') { return $null }

    $t = $Target.Split('#')[0].Trim()
    if ([string]::IsNullOrWhiteSpace($t)) { return $null }

    # Docusaurus docs routes like /docs/use/workflows
    if ($t.StartsWith('/docs/')) {
        $id = $t.Substring(6).TrimStart('/')
        $candidate1 = Join-Path $DocsRoot ($id + ".md")
        $candidate2 = Join-Path $DocsRoot ($id + ".mdx")
        if (-not (Test-Path $candidate1) -and -not (Test-Path $candidate2)) {
            return "Missing target for route $t (expected $candidate1 or $candidate2)"
        }
        return $null
    }

    # relative links
    $base = Split-Path -Parent $FromFile
    $candidate = Join-Path $base $t

    if (Test-Path $candidate) { return $null }
    if (Test-Path ($candidate + ".md")) { return $null }
    if (Test-Path ($candidate + ".mdx")) { return $null }

    return "Missing relative target '$Target' from '$FromFile' (checked $candidate[.md/.mdx])"
}

function Find-MdxRisks {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [object] $Lines
    )

    # Normalize $Lines to a string[] for safe processing
    $normalizedLines = @()
    if ($null -eq $Lines) {
        $normalizedLines = @()
    }
    elseif ($Lines -is [string]) {
        if ([string]::IsNullOrEmpty($Lines)) { $normalizedLines = @() }
        else { $normalizedLines = @($Lines) }
    }
    else {
        $normalizedLines = @($Lines)
    }

    $inFence = $false
    $risks = New-Object System.Collections.Generic.List[object]

    for ($i = 0; $i -lt $normalizedLines.Count; $i++) {
        $line = $normalizedLines[$i]

        if ($line -match '^\s*```') {
            $inFence = -not $inFence
            continue
        }
        if ($inFence) { continue }

        # Ignore any MDX-like patterns that are inside inline code.
        # Simple heuristic: split by backticks and only scan "outside" segments (even indices).
        $segments = $line -split '`'
        for ($s = 0; $s -lt $segments.Count; $s += 2) {
            $seg = $segments[$s]

            if ([string]::IsNullOrWhiteSpace($seg)) { continue }

            # JSX-like tags: <Token>
            if ($seg -match '<[A-Za-z][A-Za-z0-9_-]*>') {
                $risks.Add([pscustomobject]@{ Line = $i + 1; Type = 'JSXTag'; Snippet = $line.Trim() })
                break
            }

            # Double braces in plain text (MDX template-like)
            if ($seg -match '\{\{') {
                $risks.Add([pscustomobject]@{ Line = $i + 1; Type = 'DoubleBrace'; Snippet = $line.Trim() })
                break
            }

            # Hashtable marker in plain text
            if ($seg -match '@\{') {
                $risks.Add([pscustomobject]@{ Line = $i + 1; Type = 'Hashtable'; Snippet = $line.Trim() })
                break
            }

            # Single brace in plain text (ignore escaped braces \{ and \})
            if ($seg -match '(?<!\\)\{') {
                $risks.Add([pscustomobject]@{ Line = $i + 1; Type = 'Brace'; Snippet = $line.Trim() })
                break
            }
        }
    }

    return $risks
}

function Get-IsGitHubActions {
    [CmdletBinding()]
    param()

    return ($env:GITHUB_ACTIONS -eq 'true')
}

function Get-IsCiEnvironment {
    [CmdletBinding()]
    param()

    if (Get-IsGitHubActions) { return $true }
    if ($env:CI -eq 'true') { return $true }
    if ($env:TF_BUILD -eq 'True') { return $true }
    if ($env:BUILD_BUILDID) { return $true }

    return $false
}

function Convert-ToRepoRelativePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $RepoRoot,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $FullPath
    )

    $root = (Resolve-Path $RepoRoot).Path.TrimEnd('\', '/')
    $full = (Resolve-Path $FullPath).Path

    if ($full.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) {
        $rel = $full.Substring($root.Length).TrimStart('\', '/')
        return ($rel -replace '\\', '/')
    }

    return ($full -replace '\\', '/')
}

function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Message,

        [Parameter()]
        [ValidateSet('Gray', 'Green', 'Yellow', 'Red', 'Cyan', 'White')]
        [string] $Color = 'White'
    )

    # In CI logs, avoid ANSI noise and keep output machine-friendly.
    if (Get-IsCiEnvironment) {
        Write-Output $Message
        return
    }

    Write-Host $Message -ForegroundColor $Color
}

function Write-Section {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Title
    )

    Write-Log -Message ""
    Write-Log -Message $Title -Color Cyan
    Write-Log -Message ("-" * $Title.Length) -Color Cyan
}

function Write-GitHubAnnotation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('error', 'warning', 'notice')]
        [string] $Level,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Message,

        [Parameter()]
        [AllowEmptyString()]
        [string] $File,

        [Parameter()]
        [int] $Line = 0
    )

    if (-not (Get-IsGitHubActions)) { return }

    $parts = @()
    if (-not [string]::IsNullOrWhiteSpace($File)) {
        $parts += "file=$File"
    }
    if ($Line -gt 0) {
        $parts += "line=$Line"
    }

    if ($parts.Count -gt 0) {
        Write-Output ("::{0} {1}::{2}" -f $Level, ($parts -join ','), $Message)
    }
    else {
        Write-Output ("::{0}::{1}" -f $Level, $Message)
    }
}

function Write-DocsAuditReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [pscustomobject] $Result,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $RepoRoot,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $DocsRoot,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $WebsiteRoot,

        [Parameter()]
        [ValidateRange(1, 5000)]
        [int] $MaxDetailItems = 50,

        [Parameter()]
        [switch] $NoDetailOutput,

        [Parameter()]
        [switch] $FailOnOrphans,

        [Parameter()]
        [switch] $FailOnLinkIssues,

        [Parameter()]
        [switch] $FailOnMdxRisks,

        [Parameter()]
        [switch] $FailOnLongPages
    )

    function ConvertTo-NormalizedArray {
        [CmdletBinding()]
        param(
            [Parameter()]
            [AllowNull()]
            [object] $Value
        )

        if ($null -eq $Value) {
            return @()
        }

        # If it's a string, treat it as a single item (avoid char enumeration).
        if ($Value -is [string]) {
            if ([string]::IsNullOrWhiteSpace($Value)) {
                return @()
            }

            return @($Value)
        }

        # If it's already an array, return as-is.
        if ($Value -is [System.Array]) {
            return $Value
        }

        # Most list types (List[T], ArrayList, etc.) should enumerate safely.
        # Still: avoid the @($Value) shortcut because it triggers PowerShell's enumeration pipeline,
        # which can surface weird enumerator exceptions. We build a list explicitly.
        try {
            $items = New-Object System.Collections.Generic.List[object]

            foreach ($item in $Value) {
                $items.Add($item)
            }

            return $items.ToArray()
        }
        catch {
            # Fallback: treat the value as a single item (do NOT attempt to enumerate again).
            return , $Value
        }
    }


    function Get-CountColor {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [int] $Count
        )

        if ($Count -gt 0) { return 'Yellow' }
        return 'Green'
    }

    function Get-TakeCount {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [int] $Total,

            [Parameter(Mandatory)]
            [int] $Max
        )

        if ($Total -lt 0) { return 0 }
        if ($Max -lt 0) { return 0 }
        if ($Total -lt $Max) { return $Total }
        return $Max
    }

    function Get-Status {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [bool] $IsFail
        )

        if ($IsFail) {
            return [pscustomobject]@{ Text = 'FAIL'; Color = 'Red' }
        }

        return [pscustomobject]@{ Text = 'PASS'; Color = 'Green' }
    }

    Write-Section -Title "Docs audit summary"
    Write-Log -Message ("Docs root:     " + (Convert-ToRepoRelativePath -RepoRoot $RepoRoot -FullPath $DocsRoot)) -Color Gray
    Write-Log -Message ("Website root:  " + (Convert-ToRepoRelativePath -RepoRoot $RepoRoot -FullPath $WebsiteRoot)) -Color Gray
    Write-Log -Message ("Report JSON:   " + (Convert-ToRepoRelativePath -RepoRoot $RepoRoot -FullPath $OutputJsonPath)) -Color Gray

    # Normalize everything to arrays and remove null/empty entries early.
    $orphanIdsRaw = ConvertTo-NormalizedArray -Value $Result.OrphanDocIds
    $orphanIds = @($orphanIdsRaw | Where-Object { $null -ne $_ -and (-not [string]::IsNullOrWhiteSpace([string]$_)) })

    $linkIssuesRaw = ConvertTo-NormalizedArray -Value $Result.LinkIssues
    $linkIssues = @($linkIssuesRaw | Where-Object { $null -ne $_ })

    $mdxRisksRaw = ConvertTo-NormalizedArray -Value $Result.MdxRisks
    $mdxRisks = @($mdxRisksRaw | Where-Object { $null -ne $_ })

    $longPagesRaw = ConvertTo-NormalizedArray -Value $Result.LongPages
    $longPages = @($longPagesRaw | Where-Object { $null -ne $_ })

    $orphansCount = [int]$orphanIds.Count
    $linkIssuesCount = [int]$linkIssues.Count
    $mdxRisksCount = [int]$mdxRisks.Count
    $longPagesCount = [int]$longPages.Count

    $isFail = $false
    if ($FailOnOrphans -and $orphansCount -gt 0) { $isFail = $true }
    if ($FailOnLinkIssues -and $linkIssuesCount -gt 0) { $isFail = $true }
    if ($FailOnMdxRisks -and $mdxRisksCount -gt 0) { $isFail = $true }
    if ($FailOnLongPages -and $longPagesCount -gt 0) { $isFail = $true }

    $status = Get-Status -IsFail:$isFail

    Write-Log -Message ""
    Write-Log -Message ("Docs (audited):  " + [int]$Result.DocsFileCount) -Color White
    Write-Log -Message ("Docs (excluded): " + [int]$Result.ExcludedDocsFileCount) -Color White
    Write-Log -Message ("Sidebar docIds:  " + [int]$Result.SidebarDocIdCount) -Color White

    Write-Log -Message ""
    Write-Log -Message ("Orphans:         " + $orphansCount) -Color (Get-CountColor -Count $orphansCount)
    Write-Log -Message ("Link issues:     " + $linkIssuesCount) -Color (Get-CountColor -Count $linkIssuesCount)
    Write-Log -Message ("MDX risks:       " + $mdxRisksCount) -Color (Get-CountColor -Count $mdxRisksCount)
    Write-Log -Message ("Long pages:      " + $longPagesCount + " (warning)") -Color (Get-CountColor -Count $longPagesCount)

    Write-Log -Message ""
    Write-Log -Message ("Status:          " + $status.Text) -Color $status.Color

    if ($NoDetailOutput) { return }

    # --- Orphans ---
    if ($orphansCount -gt 0) {
        Write-Section -Title "Orphan docs (not referenced from website/sidebars.js)"

        $items = @($orphanIds | Sort-Object)
        $take = Get-TakeCount -Total $items.Count -Max $MaxDetailItems

        for ($i = 0; $i -lt $take; $i++) {
            $docId = $items[$i]

            $path = $null
            if ($null -ne $docId -and $script:docIdToPath.ContainsKey($docId)) {
                $path = $script:docIdToPath[$docId]
            }

            if ($path) {
                $rel = Convert-ToRepoRelativePath -RepoRoot $RepoRoot -FullPath $path
                Write-Log -Message ("- {0}  ({1})" -f $docId, $rel) -Color Yellow

                $level = 'warning'
                if ($FailOnOrphans) { $level = 'error' }
                Write-GitHubAnnotation -Level $level -Message ("Orphan doc not in sidebars: {0}" -f $docId) -File $rel
            }
            else {
                Write-Log -Message ("- {0}" -f $docId) -Color Yellow
            }
        }

        if ($items.Count -gt $take) {
            Write-Log -Message ("... and {0} more" -f ($items.Count - $take)) -Color Gray
        }
    }

    # --- Link issues ---
    if ($linkIssuesCount -gt 0) {
        Write-Section -Title "Broken internal links"

        # Sort defensively (properties may be missing in edge cases)
        $items = @($linkIssues | Sort-Object { $_.File }, { $_.Target })
        $take = Get-TakeCount -Total $items.Count -Max $MaxDetailItems

        for ($i = 0; $i -lt $take; $i++) {
            $it = $items[$i]
            $rel = Convert-ToRepoRelativePath -RepoRoot $RepoRoot -FullPath $it.File
            Write-Log -Message ("- {0}: {1} -> {2}" -f $rel, $it.Target, $it.Issue) -Color Yellow

            $level = 'warning'
            if ($FailOnLinkIssues) { $level = 'error' }
            Write-GitHubAnnotation -Level $level -Message ("Broken internal link: {0}" -f $it.Target) -File $rel
        }

        if ($items.Count -gt $take) {
            Write-Log -Message ("... and {0} more" -f ($items.Count - $take)) -Color Gray
        }
    }

    # --- MDX risks ---
    if ($mdxRisksCount -gt 0) {
        Write-Section -Title "MDX risks (possible accidental MDX parsing)"

        $items = @($mdxRisks | Sort-Object { $_.File }, { $_.Line }, { $_.Type })
        $take = Get-TakeCount -Total $items.Count -Max $MaxDetailItems

        for ($i = 0; $i -lt $take; $i++) {
            $it = $items[$i]
            $rel = Convert-ToRepoRelativePath -RepoRoot $RepoRoot -FullPath $it.File
            Write-Log -Message ("- {0}:{1} [{2}] {3}" -f $rel, $it.Line, $it.Type, $it.Snippet) -Color Yellow

            $level = 'warning'
            if ($FailOnMdxRisks) { $level = 'error' }
            Write-GitHubAnnotation -Level $level -Message ("MDX risk ({0}): {1}" -f $it.Type, $it.Snippet) -File $rel -Line ([int]$it.Line)
        }

        if ($items.Count -gt $take) {
            Write-Log -Message ("... and {0} more" -f ($items.Count - $take)) -Color Gray
        }
    }

    # --- Long pages ---
    if ($longPagesCount -gt 0) {
        Write-Section -Title ("Long pages (>= {0} lines)" -f $LongPageLineThreshold)

        $items = @($longPages | Sort-Object { $_.Lines } -Descending)
        $take = Get-TakeCount -Total $items.Count -Max $MaxDetailItems

        for ($i = 0; $i -lt $take; $i++) {
            $it = $items[$i]
            $rel = Convert-ToRepoRelativePath -RepoRoot $RepoRoot -FullPath $it.File
            Write-Log -Message ("- {0}: {1} lines" -f $rel, $it.Lines) -Color Yellow

            $level = 'warning'
            if ($FailOnLongPages) { $level = 'error' }
            Write-GitHubAnnotation -Level $level -Message ("Long page: {0} lines" -f $it.Lines) -File $rel
        }

        if ($items.Count -gt $take) {
            Write-Log -Message ("... and {0} more" -f ($items.Count - $take)) -Color Gray
        }
    }
}

# --- Resolve paths ---
$docsRoot = Resolve-FullPath -Path $DocsPath
$websiteRoot = Resolve-FullPath -Path $WebsitePath
$repoRoot = Resolve-FullPath -Path (Join-Path $PSScriptRoot '..')

# --- Excludes (Docusaurus + user) ---
$docusaurusExclude = @()
try {
    $docusaurusExclude = @(Get-DocusaurusDocsExcludeGlobs -WebsitePath $websiteRoot)
}
catch {
    # Do not hard-fail on config parsing; better to report and continue.
    Write-Warning $_.Exception.Message
}

$excludeGlobs = @()
$excludeGlobs += $docusaurusExclude
$excludeGlobs += $AdditionalExcludeGlobs
$excludeGlobs = @($excludeGlobs | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)

# --- Files ---
$allFiles = Get-ChildItem -Path $docsRoot -Recurse -File | Where-Object { $_.Extension -in '.md', '.mdx' }

# Determine relative paths for exclude matching.
$docsFiles = New-Object System.Collections.Generic.List[object]
$excludedFiles = New-Object System.Collections.Generic.List[object]

foreach ($f in $allFiles) {
    $rel = $f.FullName.Substring($docsRoot.Length).TrimStart('\', '/')
    $relNorm = ($rel -replace '\\', '/')

    $isExcluded = $false
    if ($excludeGlobs.Count -gt 0) {
        $isExcluded = Test-GlobMatch -PathLike $relNorm -Globs $excludeGlobs
    }

    $entry = [pscustomobject]@{
        FullName     = $f.FullName
        RelativePath = $relNorm
        IsExcluded   = $isExcluded
    }

    if ($isExcluded) {
        $excludedFiles.Add($entry)
        if ($IncludeExcludedDocs) {
            $docsFiles.Add($entry)
        }
    }
    else {
        $docsFiles.Add($entry)
    }
}

# --- Sidebar docIds ---
$sidebarIds = @()
try {
    $sidebarIds = @(Get-SidebarDocIds -WebsitePath $websiteRoot)
}
catch {
    throw "Failed to read sidebars.js: $($_.Exception.Message)"
}

# --- DocId map ---
$script:docIdToPath = @{}
foreach ($df in $docsFiles) {
    $id = Get-DocIdFromPath -DocsRoot $docsRoot -FilePath $df.FullName
    $script:docIdToPath[$id] = $df.FullName
}

# --- Orphans (excluding excluded docs implicitly, because they are not in docsFiles unless IncludeExcludedDocs) ---
$orphans = @($script:docIdToPath.Keys | Where-Object { $_ -notin $sidebarIds } | Sort-Object)

# --- Link issues and MDX risks ---
$linkIssues = New-Object System.Collections.Generic.List[object]
$mdxRisks = New-Object System.Collections.Generic.List[object]
$longPages = New-Object System.Collections.Generic.List[object]

foreach ($df in $docsFiles) {
    $raw = Get-Content -Path $df.FullName -Raw -ErrorAction Stop
    $lines = $raw -split "`r?`n"

    if ($lines.Count -ge $LongPageLineThreshold) {
        $longPages.Add([pscustomobject]@{ File = $df.FullName; Lines = $lines.Count })
    }

    foreach ($t in Get-MarkdownLinks -Content $raw) {
        $issue = Test-InternalLinkTarget -DocsRoot $docsRoot -FromFile $df.FullName -Target $t
        if ($issue) {
            $linkIssues.Add([pscustomobject]@{ File = $df.FullName; Target = $t; Issue = $issue })
        }
    }

    foreach ($r in Find-MdxRisks -Lines @($lines)) {
        $mdxRisks.Add(
            [pscustomobject]@{
                File    = $df.FullName
                Line    = $r.Line
                Type    = $r.Type
                Snippet = $r.Snippet
            }
        )
    }
}

# --- Build result ---
$result = [pscustomobject]@{
    DocsFileCount          = $docsFiles.Count
    ExcludedDocsFileCount  = $excludedFiles.Count
    SidebarDocIdCount      = $sidebarIds.Count
    ExcludeGlobsEffective  = $excludeGlobs
    OrphanDocIds           = $orphans
    LinkIssues             = $linkIssues
    MdxRisks               = $mdxRisks
    LongPages              = ($longPages | Sort-Object Lines -Descending)
}

if (-not (Test-Path -Path (Split-Path -Parent $OutputJsonPath))) {
    New-Item -ItemType Directory -Path (Split-Path -Parent $OutputJsonPath) | Out-Null
}

$result | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 -Path $OutputJsonPath
Write-Log -Message ("Wrote " + (Convert-ToRepoRelativePath -RepoRoot $repoRoot -FullPath $OutputJsonPath)) -Color Gray

$reportParams = @{
    Result         = $result
    RepoRoot       = $repoRoot
    DocsRoot       = $docsRoot
    WebsiteRoot    = $websiteRoot
    MaxDetailItems = $MaxDetailItems
    NoDetailOutput = $NoDetailOutput
    FailOnOrphans  = $FailOnOrphans
    FailOnLinkIssues = $FailOnLinkIssues
    FailOnMdxRisks   = $FailOnMdxRisks
    FailOnLongPages  = $FailOnLongPages
}

try {
    Write-DocsAuditReport @reportParams
}
catch {
    Write-Host "Docs audit failed with an unhandled exception." -ForegroundColor Red
    Write-Host ($_.Exception.GetType().FullName) -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red

    if ($_.Exception.InnerException) {
        Write-Host "InnerException:" -ForegroundColor Red
        Write-Host ($_.Exception.InnerException.GetType().FullName) -ForegroundColor Red
        Write-Host $_.Exception.InnerException.Message -ForegroundColor Red
    }

    Write-Host "" 
    Write-Host "InvocationInfo:" -ForegroundColor Red
    if ($_.InvocationInfo) {
        Write-Host ("  ScriptName:     {0}" -f $_.InvocationInfo.ScriptName) -ForegroundColor Red
        Write-Host ("  ScriptLine:     {0}" -f $_.InvocationInfo.ScriptLineNumber) -ForegroundColor Red
        Write-Host ("  OffsetInLine:   {0}" -f $_.InvocationInfo.OffsetInLine) -ForegroundColor Red
        Write-Host "  Line:" -ForegroundColor Red
        Write-Host ("  {0}" -f $_.InvocationInfo.Line) -ForegroundColor Red

        Write-Host "" 
        Write-Host "  PositionMessage:" -ForegroundColor Red
        Write-Host $_.InvocationInfo.PositionMessage -ForegroundColor Red
    }

    Write-Host "" 
    Write-Host "ScriptStackTrace:" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red

    throw
}

# --- Exit code policy for CI ---
$exitCode = 0

if ($FailOnOrphans -and $orphans.Count -gt 0) { $exitCode = 1 }
if ($FailOnLinkIssues -and $linkIssues.Count -gt 0) { $exitCode = 1 }
if ($FailOnMdxRisks -and $mdxRisks.Count -gt 0) { $exitCode = 1 }

# Long pages are warnings by default.
if ($FailOnLongPages -and $longPages.Count -gt 0) { $exitCode = 1 }

exit $exitCode

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

    # Very small glob-to-regex converter:
    # - ** matches any path segment(s)
    # - * matches any chars except path separator
    # - ? matches single char except separator
    $g = $Glob -replace '\\', '/'
    $g = [regex]::Escape($g)

    # Restore glob tokens (escaped) to regex:
    $g = $g -replace '\\\*\\\*', '___GLOBSTAR___'
    $g = $g -replace '\\\*', '___STAR___'
    $g = $g -replace '\\\?', '___Q___'

    $g = $g -replace '___GLOBSTAR___', '.*'
    $g = $g -replace '___STAR___', '[^/]*'
    $g = $g -replace '___Q___', '[^/]'

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
const path = require('path');
const cfgPath = process.argv[1];
const cfg = require(path.resolve(cfgPath));

function collectDocsExclude(config) {
  const globs = [];
  if (Array.isArray(config.presets)) {
    for (const p of config.presets) {
      if (!Array.isArray(p) || p.length < 2) continue;
      const name = p[0];
      const opts = p[1] || {};
      if (name === 'classic' || name === '@docusaurus/preset-classic') {
        if (opts.docs && Array.isArray(opts.docs.exclude)) {
          globs.push(...opts.docs.exclude);
        }
      }
    }
  }
  if (Array.isArray(config.plugins)) {
    for (const pl of config.plugins) {
      if (!Array.isArray(pl) || pl.length < 2) continue;
      const name = pl[0];
      const opts = pl[1] || {};
      if (name === '@docusaurus/plugin-content-docs' && Array.isArray(opts.exclude)) {
        globs.push(...opts.exclude);
      }
    }
  }
  return globs;
}

console.log(JSON.stringify(collectDocsExclude(cfg)));
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

    $rel = $full.Substring($root.Length).TrimStart('\','/')
    $rel = $rel -replace '\.mdx?$',''
    return ($rel -replace '\\','/')
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

# --- Resolve paths ---
$docsRoot = Resolve-FullPath -Path $DocsPath
$websiteRoot = Resolve-FullPath -Path $WebsitePath

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
    $rel = $f.FullName.Substring($docsRoot.Length).TrimStart('\','/')
    $relNorm = ($rel -replace '\\','/')

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
$docIdToPath = @{}
foreach ($df in $docsFiles) {
    $id = Get-DocIdFromPath -DocsRoot $docsRoot -FilePath $df.FullName
    $docIdToPath[$id] = $df.FullName
}

# --- Orphans (excluding excluded docs implicitly, because they are not in docsFiles unless IncludeExcludedDocs) ---
$orphans = @($docIdToPath.Keys | Where-Object { $_ -notin $sidebarIds } | Sort-Object)

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
        $mdxRisks.Add([pscustomobject]@{
            File    = $df.FullName
            Line    = $r.Line
            Type    = $r.Type
            Snippet = $r.Snippet
        })
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
Write-Host "Wrote $OutputJsonPath"

Write-Host ("Docs (audited): " + $docsFiles.Count)
Write-Host ("Docs (excluded): " + $excludedFiles.Count)
Write-Host ("Sidebar docIds: " + $sidebarIds.Count)

Write-Host ("Orphans: " + $orphans.Count)
Write-Host ("Link issues: " + $linkIssues.Count)
Write-Host ("MDX risks: " + $mdxRisks.Count)
Write-Host ("Long pages (warning): " + $longPages.Count)

# --- Exit code policy for CI ---
$exitCode = 0

if ($FailOnOrphans -and $orphans.Count -gt 0) { $exitCode = 1 }
if ($FailOnLinkIssues -and $linkIssues.Count -gt 0) { $exitCode = 1 }
if ($FailOnMdxRisks -and $mdxRisks.Count -gt 0) { $exitCode = 1 }

# Long pages are warnings by default.
if ($FailOnLongPages -and $longPages.Count -gt 0) { $exitCode = 1 }

exit $exitCode

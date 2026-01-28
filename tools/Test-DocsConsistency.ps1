param(
    [string]$DocsPath = ".\docs",
    [string]$WebsitePath = ".\website",
    [int]$LongPageLineThreshold = 350
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-SidebarDocIds {
    param([string]$WebsitePath)

    $sidebarsJs = Join-Path $WebsitePath "sidebars.js"
    if (-not (Test-Path $sidebarsJs)) {
        Write-Warning "sidebars.js not found: $sidebarsJs"
        return @()
    }

    # Require the JS and print JSON
    $nodeCmd = (Get-Command node -ErrorAction Stop).Source

    $json = & $nodeCmd -e "console.log(JSON.stringify(require('./website/sidebars.js')))"
    $sb = $json | ConvertFrom-Json

    $ids = New-Object System.Collections.Generic.List[string]

    function Visit($n) {
        if ($null -eq $n) { return }

        # string docId
        if ($n -is [string]) {
            $ids.Add($n)
            return
        }

        # arrays / enumerables (but NOT string)
        if (($n -is [System.Collections.IEnumerable]) -and -not ($n -is [string])) {
            foreach ($item in $n) { Visit $item }
            return
        }

        # PSObject/hashtable-like: iterate values safely
        if ($n -is [psobject]) {
            foreach ($p in $n.PSObject.Properties) {
                Visit $p.Value
            }
            return
        }
    }

    Visit $sb
    $ids | Select-Object -Unique
}

function Get-DocIdFromPath {
    param([string]$DocsPath, [string]$FilePath)

    $rel = Resolve-Path $FilePath | ForEach-Object {
        $_.Path.Substring((Resolve-Path $DocsPath).Path.Length).TrimStart('\', '/')
    }
    $rel -replace '\.mdx?$', '' -replace '\\', '/'
}

function Get-MarkdownLinks {
    param([string]$Content)
    # matches [text](target) ignoring images ![...](...)
    $pattern = '(?<!!)\[[^\]]*\]\((?<t>[^)]+)\)'
    [regex]::Matches($Content, $pattern) | ForEach-Object { $_.Groups['t'].Value }
}

function Test-InternalLinkTarget {
    param(
        [string]$DocsPath,
        [string]$FromFile,
        [string]$Target
    )

    # ignore external
    if ($Target -match '^(https?:)?//') { return $null }
    if ($Target -match '^(mailto:|tel:)') { return $null }

    $t = $Target.Split('#')[0].Trim()

    if ([string]::IsNullOrWhiteSpace($t)) { return $null }

    # Docusaurus absolute docs routes like /docs/use/workflows
    if ($t.StartsWith('/docs/')) {
        $id = $t.Substring(6).TrimStart('/')
        $candidate1 = Join-Path $DocsPath ($id + ".md")
        $candidate2 = Join-Path $DocsPath ($id + ".mdx")
        if (-not (Test-Path $candidate1) -and -not (Test-Path $candidate2)) {
            return "Missing target for route $t (expected $candidate1 or $candidate2)"
        }
        return $null
    }

    # site static assets /assets/...
    if ($t.StartsWith('/assets/')) {
        $candidate = Join-Path $DocsPath $t.TrimStart('/')
        if (-not (Test-Path $candidate)) {
            return "Missing asset $t (expected $candidate)"
        }
        return $null
    }

    # relative links
    $base = Split-Path -Parent $FromFile
    $candidate = Join-Path $base $t
    # allow .md omitted
    if (Test-Path $candidate) { return $null }
    if (Test-Path ($candidate + ".md")) { return $null }
    if (Test-Path ($candidate + ".mdx")) { return $null }

    return "Missing relative target '$Target' from '$FromFile' (checked $candidate[.md/.mdx])"
}

function Find-MdxRisks {
    param([string[]]$Lines)

    $inFence = $false
    $risks = New-Object System.Collections.Generic.List[object]

    for ($i = 0; $i -lt $Lines.Count; $i++) {
        $line = $Lines[$i]

        if ($line -match '^\s*```') {
            $inFence = -not $inFence
            continue
        }
        if ($inFence) { continue }

        # JSX-like tags
        if ($line -match '<[A-Za-z][A-Za-z0-9]*>') {
            $risks.Add([pscustomobject]@{ Line = $i + 1; Type = 'JSXTag'; Snippet = $line.Trim() })
        }
        # template braces
        if ($line -match '\{\{') {
            $risks.Add([pscustomobject]@{ Line = $i + 1; Type = 'DoubleBrace'; Snippet = $line.Trim() })
        }
        # hashtables outside code
        if ($line -match '@\{') {
            $risks.Add([pscustomobject]@{ Line = $i + 1; Type = 'Hashtable'; Snippet = $line.Trim() })
        }
        # single brace risks (heuristic)
        if ($line -match '(?<!`)({)(?!`)') {
            # avoid false positives: markdown tables etc. – still useful to review
            $risks.Add([pscustomobject]@{ Line = $i + 1; Type = 'Brace'; Snippet = $line.Trim() })
        }
    }

    $risks
}

# --- Run audit ---
$docs = Resolve-Path $DocsPath
$files = Get-ChildItem -Path $docs -Recurse -File | Where-Object { $_.Extension -in '.md', '.mdx' }

$sidebarIds = Get-SidebarDocIds -WebsitePath $WebsitePath
$docIds = @{}
foreach ($f in $files) {
    $id = Get-DocIdFromPath -DocsPath $docs.Path -FilePath $f.FullName
    $docIds[$id] = $f.FullName
}

$orphans = $docIds.Keys | Where-Object { $_ -notin $sidebarIds } | Sort-Object

$linkIssues = New-Object System.Collections.Generic.List[object]
$mdxRisks = New-Object System.Collections.Generic.List[object]
$longPages = New-Object System.Collections.Generic.List[object]

foreach ($f in $files) {
    $content = Get-Content $f.FullName -Raw
    $lines = $content -split "`r?`n"

    if ($lines.Count -ge $LongPageLineThreshold) {
        $longPages.Add([pscustomobject]@{ File = $f.FullName; Lines = $lines.Count })
    }

    foreach ($t in Get-MarkdownLinks -Content $content) {
        $issue = Test-InternalLinkTarget -DocsPath $docs.Path -FromFile $f.FullName -Target $t
        if ($issue) {
            $linkIssues.Add([pscustomobject]@{ File = $f.FullName; Target = $t; Issue = $issue })
        }
    }

    foreach ($r in Find-MdxRisks -Lines $lines) {
        $mdxRisks.Add([pscustomobject]@{ File = $f.FullName; Line = $r.Line; Type = $r.Type; Snippet = $r.Snippet })
    }
}

$result = [pscustomobject]@{
    DocsFileCount     = $files.Count
    SidebarDocIdCount = $sidebarIds.Count
    OrphanDocIds      = $orphans
    LinkIssues        = $linkIssues
    MdxRisks          = $mdxRisks
    LongPages         = $longPages | Sort-Object Lines -Descending
}

$result | ConvertTo-Json -Depth 6 | Set-Content -Encoding UTF8 ".\docs-audit.json"
Write-Host "Wrote docs-audit.json"
Write-Host ("Orphans: " + $orphans.Count)
Write-Host ("Link issues: " + $linkIssues.Count)
Write-Host ("MDX risks: " + $mdxRisks.Count)
Write-Host ("Long pages: " + $longPages.Count)

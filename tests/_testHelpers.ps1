Set-StrictMode -Version Latest

function Get-RepoRootPath {
    [CmdletBinding()]
    param()

    # tests/ is expected to be located in repo root.
    return (Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')).Path
}

function Get-ModuleManifestPaths {
    [CmdletBinding()]
    param()

    $repoRoot = Get-RepoRootPath
    $srcRoot = Join-Path -Path $repoRoot -ChildPath 'src'

    # module manifests only (one level deep)
    return Get-ChildItem -Path $srcRoot -Filter '*.psd1' -File -Recurse |
        Where-Object { $_.FullName -match [regex]::Escape([IO.Path]::Combine('src', '')) } |
        Where-Object { $_.Directory.Parent -and $_.Directory.Parent.Name -eq 'src' } |
        Select-Object -ExpandProperty FullName
}

Set-StrictMode -Version Latest

BeforeAll {
    . (Join-Path (Split-Path -Path $PSScriptRoot -Parent) '_testHelpers.ps1')
    Import-IdleTestModule
}

Describe 'Module manifests' {
    It 'All module manifests under src/ are valid' {
        $paths = Get-ModuleManifestPaths
        $paths | Should -Not -BeNullOrEmpty

        foreach ($path in $paths) {
            { Test-ModuleManifest -Path $path -ErrorAction Stop } | Should -Not -Throw
        }
    }
}

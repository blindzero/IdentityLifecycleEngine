Set-StrictMode -Version Latest

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '_testHelpers.ps1')

    $repoRoot = Get-RepoRootPath
    $idleManifest = Join-Path -Path $repoRoot -ChildPath 'src/IdLE/IdLE.psd1'

    Remove-Module -Name IdLE, IdLE.Core -Force -ErrorAction SilentlyContinue
    Import-Module -Name $idleManifest -Force -ErrorAction Stop

    $workflowsPath = Join-Path -Path $repoRoot -ChildPath 'examples/workflows'
}

Describe 'Example workflows' {
    It 'All workflow PSD1 files validate' {
        $files = Get-ChildItem -Path $workflowsPath -Filter '*.psd1' -File
        $files | Should -Not -BeNullOrEmpty

        foreach ($file in $files) {
            { Test-IdleWorkflow -WorkflowPath $file.FullName } | Should -Not -Throw
        }
    }
}

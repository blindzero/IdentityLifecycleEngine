Set-StrictMode -Version Latest

BeforeAll {
    . (Join-Path $PSScriptRoot '_testHelpers.ps1')
    Import-IdleTestModule

    $workflowsPath = Join-Path -Path (Get-RepoRootPath) -ChildPath 'examples/workflows'
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

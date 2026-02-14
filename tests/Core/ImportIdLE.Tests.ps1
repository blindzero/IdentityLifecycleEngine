Set-StrictMode -Version Latest

BeforeAll {
    . (Join-Path (Split-Path -Path $PSScriptRoot -Parent) '_testHelpers.ps1')
    $script:RepoRoot = Get-RepoRootPath
    $script:ImportScript = Join-Path -Path $script:RepoRoot -ChildPath 'tools/import-idle.ps1'
}

Describe 'Import-IdLE helper script' {
    Context 'Script discovery' {
        It 'import-idle.ps1 script exists' {
            $script:ImportScript | Should -Exist
        }

        It 'import-idle.ps1 finds workflows in subdirectories' {
            $workflowDir = Join-Path -Path $script:RepoRoot -ChildPath 'examples/workflows'

            $mockWorkflows = Get-ChildItem -Path (Join-Path $workflowDir 'mock') -Filter '*.psd1' -File -ErrorAction SilentlyContinue
            $templateWorkflows = Get-ChildItem -Path (Join-Path $workflowDir 'templates') -Filter '*.psd1' -File -ErrorAction SilentlyContinue

            $mockWorkflows | Should -Not -BeNullOrEmpty
            $templateWorkflows | Should -Not -BeNullOrEmpty

            $allWorkflows = Get-ChildItem -Path $workflowDir -Filter '*.psd1' -File -Recurse
            $allWorkflows | Should -Not -BeNullOrEmpty
            $allWorkflows.Count | Should -BeGreaterThan 5
        }
    }

    Context 'Execution' {
        It 'import-idle.ps1 executes without errors' {
            { & $script:ImportScript -ErrorAction Stop } | Should -Not -Throw
        }
    }
}

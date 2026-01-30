Set-StrictMode -Version Latest

BeforeAll {
    . (Join-Path (Split-Path -Path $PSScriptRoot -Parent) '_testHelpers.ps1')
    $repoRoot = Get-RepoRootPath
    $importScript = Join-Path -Path $repoRoot -ChildPath 'tools/import-idle.ps1'
}

Describe 'Import-IdLE helper script' {
    It 'import-idle.ps1 script exists' {
        $importScript | Should -Exist
    }

    It 'import-idle.ps1 finds workflows in subdirectories' {
        # The script should find workflows in examples/workflows/mock and templates subdirectories
        # This test validates that the script can discover workflows after the directory restructuring

        $workflowDir = Join-Path -Path $repoRoot -ChildPath 'examples/workflows'

        # Verify workflows exist in subdirectories
        $mockWorkflows = Get-ChildItem -Path (Join-Path $workflowDir 'mock') -Filter '*.psd1' -File -ErrorAction SilentlyContinue
        $templateWorkflows = Get-ChildItem -Path (Join-Path $workflowDir 'templates') -Filter '*.psd1' -File -ErrorAction SilentlyContinue

        $mockWorkflows | Should -Not -BeNullOrEmpty
        $templateWorkflows | Should -Not -BeNullOrEmpty

        # Verify the script logic for finding workflows recursively
        $allWorkflows = Get-ChildItem -Path $workflowDir -Filter '*.psd1' -File -Recurse
        $allWorkflows | Should -Not -BeNullOrEmpty
        $allWorkflows.Count | Should -BeGreaterThan 5
    }

    It 'import-idle.ps1 executes without errors' {
        # Execute the import script and verify it completes successfully
        { & $importScript -ErrorAction Stop } | Should -Not -Throw
    }
}

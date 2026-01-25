Set-StrictMode -Version Latest

BeforeAll {
    . (Join-Path (Split-Path -Path $PSScriptRoot -Parent) '_testHelpers.ps1')
    Import-IdleTestModule

    $workflowsPath = Join-Path -Path (Get-RepoRootPath) -ChildPath 'examples/workflows'
}

Describe 'Mock example workflows' {
    BeforeAll {
        $mockWorkflowsPath = Join-Path -Path $workflowsPath -ChildPath 'mock'
        $mockWorkflows = Get-ChildItem -Path $mockWorkflowsPath -Filter '*.psd1' -File -ErrorAction SilentlyContinue
    }

    It 'Mock workflow directory exists' {
        $mockWorkflowsPath | Should -Exist
    }

    It 'Mock workflows exist' {
        $mockWorkflows | Should -Not -BeNullOrEmpty
    }

    It 'All mock workflows validate with Test-IdleWorkflow' {
        foreach ($file in $mockWorkflows) {
            { Test-IdleWorkflow -WorkflowPath $file.FullName } | Should -Not -Throw
        }
    }

    It 'All mock workflows can create a plan with Mock provider' {
        $providers = @{
            Identity = New-IdleMockIdentityProvider
        }

        foreach ($file in $mockWorkflows) {
            $workflow = Import-PowerShellDataFile -Path $file.FullName
            $lifecycleEvent = if ($workflow.ContainsKey('LifecycleEvent')) { $workflow.LifecycleEvent } else { 'Joiner' }
            $request = New-IdleLifecycleRequest -LifecycleEvent $lifecycleEvent -Actor 'test-user'
            
            { New-IdlePlan -WorkflowPath $file.FullName -Request $request -Providers $providers } | Should -Not -Throw
        }
    }

    It 'All mock workflows execute successfully with Mock provider' {
        $providers = @{
            Identity = New-IdleMockIdentityProvider
        }

        foreach ($file in $mockWorkflows) {
            $workflow = Import-PowerShellDataFile -Path $file.FullName
            $lifecycleEvent = if ($workflow.ContainsKey('LifecycleEvent')) { $workflow.LifecycleEvent } else { 'Joiner' }
            $request = New-IdleLifecycleRequest -LifecycleEvent $lifecycleEvent -Actor 'test-user'
            
            $plan = New-IdlePlan -WorkflowPath $file.FullName -Request $request -Providers $providers
            $result = Invoke-IdlePlan -Plan $plan -Providers $providers
            
            $result.Status | Should -Be 'Completed' -Because "Mock workflow '$($file.Name)' should complete successfully"
        }
    }
}

Describe 'Live example workflows' {
    BeforeAll {
        $liveWorkflowsPath = Join-Path -Path $workflowsPath -ChildPath 'live'
        $liveWorkflows = Get-ChildItem -Path $liveWorkflowsPath -Filter '*.psd1' -File -ErrorAction SilentlyContinue
    }

    It 'Live workflow directory exists' {
        $liveWorkflowsPath | Should -Exist
    }

    It 'Live workflows exist' {
        $liveWorkflows | Should -Not -BeNullOrEmpty
    }

    It 'All live workflows validate with Test-IdleWorkflow' {
        foreach ($file in $liveWorkflows) {
            { Test-IdleWorkflow -WorkflowPath $file.FullName } | Should -Not -Throw
        }
    }
}

Describe 'Template example workflows' {
    BeforeAll {
        $templatesWorkflowsPath = Join-Path -Path $workflowsPath -ChildPath 'templates'
        $templateWorkflows = Get-ChildItem -Path $templatesWorkflowsPath -Filter '*.psd1' -File -ErrorAction SilentlyContinue
    }

    It 'Templates workflow directory exists' {
        $templatesWorkflowsPath | Should -Exist
    }

    It 'All template workflows validate with Test-IdleWorkflow (if any exist)' {
        if ($templateWorkflows) {
            foreach ($file in $templateWorkflows) {
                { Test-IdleWorkflow -WorkflowPath $file.FullName } | Should -Not -Throw
            }
        } else {
            Set-ItResult -Skipped -Because 'No template workflows exist yet'
        }
    }
}

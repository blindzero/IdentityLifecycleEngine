Set-StrictMode -Version Latest

BeforeAll {
    . (Join-Path (Split-Path -Path $PSScriptRoot -Parent) '_testHelpers.ps1')
    Import-IdleTestModule

    $workflowsPath = Join-Path -Path (Get-RepoRootPath) -ChildPath 'examples/workflows'
}

Describe 'Example workflows' {
    Context 'Mock workflows' {
        BeforeAll {
            $mockWorkflowsPath = Join-Path -Path $workflowsPath -ChildPath 'mock'
            $mockWorkflows = Get-ChildItem -Path $mockWorkflowsPath -Filter '*.psd1' -File -ErrorAction SilentlyContinue
        }

        It 'discovers mock workflow files' {
            $mockWorkflowsPath | Should -Exist
            $mockWorkflows | Should -Not -BeNullOrEmpty
        }

        It 'validates mock workflows with Test-IdleWorkflow' {
            foreach ($file in $mockWorkflows) {
                { Test-IdleWorkflow -WorkflowPath $file.FullName } | Should -Not -Throw
            }
        }

        It 'creates a plan for every mock workflow' {
            $providers = @{ Identity = New-IdleMockIdentityProvider }

            foreach ($file in $mockWorkflows) {
                $workflow = Import-PowerShellDataFile -Path $file.FullName
                $lifecycleEvent = if ($workflow.ContainsKey('LifecycleEvent')) { $workflow.LifecycleEvent } else { 'Joiner' }
                
                # Provide sample data for workflows that use templates
                $desiredState = @{
                    IdentityKey = 'test-user'
                    GivenName   = 'Test'
                    Surname     = 'User'
                    Department  = 'IT'
                    Title       = 'Engineer'
                    GroupId     = 'test-group-id'
                    GroupName   = 'Test Group'
                }
                
                $request = New-IdleTestRequest -LifecycleEvent $lifecycleEvent -Actor 'test-user' -DesiredState $desiredState
            
                { New-IdlePlan -WorkflowPath $file.FullName -Request $request -Providers $providers } | Should -Not -Throw
            }
        }

        It 'executes every mock workflow successfully' {
            $providers = @{ Identity = New-IdleMockIdentityProvider }

            foreach ($file in $mockWorkflows) {
                $workflow = Import-PowerShellDataFile -Path $file.FullName
                $lifecycleEvent = if ($workflow.ContainsKey('LifecycleEvent')) { $workflow.LifecycleEvent } else { 'Joiner' }
                
                # Provide sample data for workflows that use templates
                $desiredState = @{
                    IdentityKey = 'test-user'
                    GivenName   = 'Test'
                    Surname     = 'User'
                    Department  = 'IT'
                    Title       = 'Engineer'
                    GroupId     = 'test-group-id'
                    GroupName   = 'Test Group'
                }
                
                $request = New-IdleTestRequest -LifecycleEvent $lifecycleEvent -Actor 'test-user' -DesiredState $desiredState
            
                $plan = New-IdlePlan -WorkflowPath $file.FullName -Request $request -Providers $providers
                $result = Invoke-IdlePlan -Plan $plan -Providers $providers
            
                $result.Status | Should -Be 'Completed' -Because "Mock workflow '$($file.Name)' should complete successfully"
            }
        }
    }

    Context 'Template workflows' {
        BeforeAll {
            $templatesWorkflowsPath = Join-Path -Path $workflowsPath -ChildPath 'templates'
            $templateWorkflows = Get-ChildItem -Path $templatesWorkflowsPath -Filter '*.psd1' -File -ErrorAction SilentlyContinue
        }

        It 'discovers template workflow files' {
            $templatesWorkflowsPath | Should -Exist
        }

        It 'validates template workflows (if any exist)' {
            if ($templateWorkflows) {
                foreach ($file in $templateWorkflows) {
                    # Load the file to check its structure
                    $content = Import-PowerShellDataFile -Path $file.FullName
                    
                    # Skip template library files (with Metadata + Workflow structure)
                    # These are documentation/reference templates, not executable workflows
                    if ($content.ContainsKey('Metadata') -and $content.ContainsKey('Workflow')) {
                        Write-Verbose "Skipping template library file: $($file.Name)"
                        continue
                    }
                    
                    { Test-IdleWorkflow -WorkflowPath $file.FullName } | Should -Not -Throw
                }
            } else {
                Set-ItResult -Skipped -Because 'No template workflows exist yet'
            }
        }
    }
}


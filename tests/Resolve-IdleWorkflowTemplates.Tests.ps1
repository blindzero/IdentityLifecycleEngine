BeforeAll {
    . (Join-Path $PSScriptRoot '_testHelpers.ps1')
    Import-IdleTestModule
    
    # Helper to get fixture workflow path
    function Get-TemplateTestFixture {
        param([string]$Name)
        return Join-Path $PSScriptRoot "fixtures/workflows/template-tests/$Name.psd1"
    }
}

Describe 'Template Substitution' {
    Context 'Single placeholder substitution' {
        It 'resolves a simple Request.Input placeholder' {
            $wfPath = Get-TemplateTestFixture 'template-simple'

            $req = New-IdleLifecycleRequest -LifecycleEvent 'Joiner' -DesiredState @{
                UserPrincipalName = 'jdoe@example.com'
            }
            $providers = @{
                StepRegistry = @{
                    'IdLE.Step.Test' = 'Invoke-IdleTestNoopStep'
                }
                StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.Test')
            }

            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

            $plan.Steps[0].With.UserName | Should -Be 'jdoe@example.com'
        }

        It 'resolves Request.DesiredState placeholder directly' {
            $wfPath = Get-TemplateTestFixture 'template-desiredstate'

            $req = New-IdleLifecycleRequest -LifecycleEvent 'Joiner' -DesiredState @{
                Department = 'Engineering'
            }
            $providers = @{
                StepRegistry = @{
                    'IdLE.Step.Test' = 'Invoke-IdleTestNoopStep'
                }
                StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.Test')
            }

            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

            $plan.Steps[0].With.Department | Should -Be 'Engineering'
        }
    }

    Context 'Multiple placeholders in one string' {
        It 'resolves multiple placeholders in a single string' {
            $wfPath = Get-TemplateTestFixture 'template-multiple'

            $req = New-IdleLifecycleRequest -LifecycleEvent 'Joiner' -DesiredState @{
                DisplayName       = 'John Doe'
                UserPrincipalName = 'jdoe@example.com'
            }
            $providers = @{
                StepRegistry = @{
                    'IdLE.Step.Test' = 'Invoke-IdleTestNoopStep'
                }
                StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.Test')
            }

            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

            $plan.Steps[0].With.Message | Should -Be 'User John Doe (jdoe@example.com) is joining.'
        }
    }

    Context 'Nested hashtable and array substitution' {
        It 'resolves templates in nested hashtables' {
            $wfPath = Get-TemplateTestFixture 'template-nested-hash'

            $req = New-IdleLifecycleRequest -LifecycleEvent 'Joiner' -DesiredState @{
                DisplayName = 'Jane Smith'
                Mail        = 'jsmith@example.com'
            }
            $providers = @{
                StepRegistry = @{
                    'IdLE.Step.Test' = 'Invoke-IdleTestNoopStep'
                }
                StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.Test')
            }

            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

            $plan.Steps[0].With.User.Name | Should -Be 'Jane Smith'
            $plan.Steps[0].With.User.Email | Should -Be 'jsmith@example.com'
        }

        It 'resolves templates in arrays' {
            $wfPath = Get-TemplateTestFixture 'template-array'

            $req = New-IdleLifecycleRequest -LifecycleEvent 'Joiner' -DesiredState @{
                PrimaryEmail   = 'primary@example.com'
                SecondaryEmail = 'secondary@example.com'
            }
            $providers = @{
                StepRegistry = @{
                    'IdLE.Step.Test' = 'Invoke-IdleTestNoopStep'
                }
                StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.Test')
            }

            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

            $plan.Steps[0].With.Emails[0] | Should -Be 'primary@example.com'
            $plan.Steps[0].With.Emails[1] | Should -Be 'secondary@example.com'
        }
    }

    Context 'Invalid syntax handling' {
        It 'throws on unbalanced opening brace' {
            $wfPath = Get-TemplateTestFixture 'template-unbalanced-open'

            $req = New-IdleLifecycleRequest -LifecycleEvent 'Joiner' -DesiredState @{ Name = 'Test' }
            $providers = @{
                StepRegistry = @{ 'IdLE.Step.Test' = 'Invoke-IdleTestNoopStep' }
                StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.Test')
            }

            { New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers } |
                Should -Throw -ExpectedMessage '*Unbalanced braces*'
        }

        It 'throws on unbalanced closing brace' {
            $wfPath = Get-TemplateTestFixture 'template-unbalanced-close'

            $req = New-IdleLifecycleRequest -LifecycleEvent 'Joiner' -DesiredState @{ Name = 'Test' }
            $providers = @{
                StepRegistry = @{ 'IdLE.Step.Test' = 'Invoke-IdleTestNoopStep' }
                StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.Test')
            }

            { New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers } |
                Should -Throw -ExpectedMessage '*Unbalanced braces*'
        }
    }

    Context 'Invalid path patterns' {
        It 'throws on path with spaces' {
            $wfPath = Get-TemplateTestFixture 'template-path-spaces'

            $req = New-IdleLifecycleRequest -LifecycleEvent 'Joiner' -DesiredState @{ UserName = 'Test' }
            $providers = @{
                StepRegistry = @{ 'IdLE.Step.Test' = 'Invoke-IdleTestNoopStep' }
                StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.Test')
            }

            { New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers } |
                Should -Throw -ExpectedMessage '*Invalid path pattern*'
        }

        It 'throws on path with special characters' {
            $wfPath = Get-TemplateTestFixture 'template-path-special'

            $req = New-IdleLifecycleRequest -LifecycleEvent 'Joiner' -DesiredState @{ UserName = 'Test' }
            $providers = @{
                StepRegistry = @{ 'IdLE.Step.Test' = 'Invoke-IdleTestNoopStep' }
                StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.Test')
            }

            { New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers } |
                Should -Throw -ExpectedMessage '*Invalid path pattern*'
        }
    }

    Context 'Missing path segments' {
        It 'throws when path does not exist' {
            $wfPath = Get-TemplateTestFixture 'template-missing-path'

            $req = New-IdleLifecycleRequest -LifecycleEvent 'Joiner' -DesiredState @{ Name = 'Test' }
            $providers = @{
                StepRegistry = @{ 'IdLE.Step.Test' = 'Invoke-IdleTestNoopStep' }
                StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.Test')
            }

            { New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers } |
                Should -Throw -ExpectedMessage '*resolved to null or does not exist*'
        }
    }

    Context 'Null resolved values' {
        It 'throws when resolved value is null' {
            $wfPath = Get-TemplateTestFixture 'template-null-value'

            $req = New-IdleLifecycleRequest -LifecycleEvent 'Joiner' -DesiredState @{ NullField = $null }
            $providers = @{
                StepRegistry = @{ 'IdLE.Step.Test' = 'Invoke-IdleTestNoopStep' }
                StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.Test')
            }

            { New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers } |
                Should -Throw -ExpectedMessage '*resolved to null*'
        }
    }

    Context 'Disallowed root access' {
        It 'throws when accessing Plan root' {
            $wfPath = Get-TemplateTestFixture 'template-plan-root'

            $req = New-IdleLifecycleRequest -LifecycleEvent 'Joiner' -DesiredState @{ Name = 'Test' }
            $providers = @{
                StepRegistry = @{ 'IdLE.Step.Test' = 'Invoke-IdleTestNoopStep' }
                StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.Test')
            }

            { New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers } |
                Should -Throw -ExpectedMessage '*is not allowed*'
        }

        It 'throws when accessing Providers root' {
            $wfPath = Get-TemplateTestFixture 'template-providers-root'

            $req = New-IdleLifecycleRequest -LifecycleEvent 'Joiner' -DesiredState @{ Name = 'Test' }
            $providers = @{
                StepRegistry = @{ 'IdLE.Step.Test' = 'Invoke-IdleTestNoopStep' }
                StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.Test')
            }

            { New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers } |
                Should -Throw -ExpectedMessage '*is not allowed*'
        }

        It 'throws when accessing Workflow root' {
            $wfPath = Get-TemplateTestFixture 'template-workflow-root'

            $req = New-IdleLifecycleRequest -LifecycleEvent 'Joiner' -DesiredState @{ Name = 'Test' }
            $providers = @{
                StepRegistry = @{ 'IdLE.Step.Test' = 'Invoke-IdleTestNoopStep' }
                StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.Test')
            }

            { New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers } |
                Should -Throw -ExpectedMessage '*is not allowed*'
        }
    }

    Context 'Request.Input alias behavior' {
        It 'uses Request.Input when Input property exists' {
            $wfPath = Get-TemplateTestFixture 'template-input-exists'

            # Create a request with explicit Input property
            $req = [pscustomobject]@{
                PSTypeName     = 'IdLE.LifecycleRequest'
                LifecycleEvent = 'Joiner'
                CorrelationId  = [guid]::NewGuid().ToString()
                Input          = @{ Name = 'FromInput' }
                DesiredState   = @{ Name = 'FromDesiredState' }
            }

            $providers = @{
                StepRegistry = @{ 'IdLE.Step.Test' = 'Invoke-IdleTestNoopStep' }
                StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.Test')
            }

            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

            $plan.Steps[0].With.Value | Should -Be 'FromInput'
        }

        It 'aliases Request.Input to Request.DesiredState when Input does not exist' {
            $wfPath = Get-TemplateTestFixture 'template-input-alias'

            # Use standard request without explicit Input property
            $req = New-IdleLifecycleRequest -LifecycleEvent 'Joiner' -DesiredState @{
                Name = 'FromDesiredState'
            }

            $providers = @{
                StepRegistry = @{ 'IdLE.Step.Test' = 'Invoke-IdleTestNoopStep' }
                StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.Test')
            }

            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

            $plan.Steps[0].With.Value | Should -Be 'FromDesiredState'
        }
    }

    Context 'Escaping' {
        It 'handles escaped opening braces' {
            $wfPath = Get-TemplateTestFixture 'template-escaped'

            $req = New-IdleLifecycleRequest -LifecycleEvent 'Joiner' -DesiredState @{ Name = 'Test' }
            $providers = @{
                StepRegistry = @{ 'IdLE.Step.Test' = 'Invoke-IdleTestNoopStep' }
                StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.Test')
            }

            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

            $plan.Steps[0].With.Value | Should -Be 'Literal {{ braces here'
        }

        It 'handles escaped braces mixed with templates' {
            $wfPath = Get-TemplateTestFixture 'template-escaped-mixed'

            $req = New-IdleLifecycleRequest -LifecycleEvent 'Joiner' -DesiredState @{ Name = 'TestName' }
            $providers = @{
                StepRegistry = @{ 'IdLE.Step.Test' = 'Invoke-IdleTestNoopStep' }
                StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.Test')
            }

            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

            $plan.Steps[0].With.Value | Should -Be 'Literal {{ and template TestName'
        }
    }

    Context 'OnFailureSteps template resolution' {
        It 'resolves templates in OnFailureSteps' {
            $wfPath = Get-TemplateTestFixture 'template-onfailure'

            $req = New-IdleLifecycleRequest -LifecycleEvent 'Joiner' -DesiredState @{
                Name              = 'John Doe'
                UserPrincipalName = 'jdoe@example.com'
            }
            $providers = @{
                StepRegistry = @{
                    'IdLE.Step.Test' = 'Invoke-IdleTestNoopStep'
                }
                StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.Test')
            }

            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

            $plan.Steps[0].With.Value | Should -Be 'John Doe'
            $plan.OnFailureSteps[0].With.ErrorMessage | Should -Be 'Failed for user jdoe@example.com'
        }
    }

    Context 'Allowed roots' {
        It 'allows Request.LifecycleEvent' {
            $wfPath = Get-TemplateTestFixture 'template-lifecycle-event'

            $req = New-IdleLifecycleRequest -LifecycleEvent 'Joiner' -DesiredState @{ Name = 'Test' }
            $providers = @{
                StepRegistry = @{ 'IdLE.Step.Test' = 'Invoke-IdleTestNoopStep' }
                StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.Test')
            }

            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

            $plan.Steps[0].With.Event | Should -Be 'Joiner'
        }

        It 'allows Request.CorrelationId' {
            $wfPath = Get-TemplateTestFixture 'template-correlation-id'

            $req = New-IdleLifecycleRequest -LifecycleEvent 'Joiner' -DesiredState @{ Name = 'Test' }
            $providers = @{
                StepRegistry = @{ 'IdLE.Step.Test' = 'Invoke-IdleTestNoopStep' }
                StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.Test')
            }

            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

            $plan.Steps[0].With.Id | Should -Be $req.CorrelationId
        }

        It 'allows Request.Actor' {
            $wfPath = Get-TemplateTestFixture 'template-actor'

            $req = New-IdleLifecycleRequest -LifecycleEvent 'Joiner' -DesiredState @{ Name = 'Test' } -Actor 'admin@example.com'
            $providers = @{
                StepRegistry = @{ 'IdLE.Step.Test' = 'Invoke-IdleTestNoopStep' }
                StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.Test')
            }

            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

            $plan.Steps[0].With.ActorName | Should -Be 'admin@example.com'
        }
    }

    Context 'Type handling' {
        It 'resolves numeric types to strings' {
            $wfPath = Get-TemplateTestFixture 'template-numeric'

            $req = New-IdleLifecycleRequest -LifecycleEvent 'Joiner' -DesiredState @{ UserId = 12345 }
            $providers = @{
                StepRegistry = @{ 'IdLE.Step.Test' = 'Invoke-IdleTestNoopStep' }
                StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.Test')
            }

            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

            $plan.Steps[0].With.Value | Should -Be 'ID: 12345'
        }

        It 'resolves boolean types to strings' {
            $wfPath = Get-TemplateTestFixture 'template-boolean'

            $req = New-IdleLifecycleRequest -LifecycleEvent 'Joiner' -DesiredState @{ IsEnabled = $true }
            $providers = @{
                StepRegistry = @{ 'IdLE.Step.Test' = 'Invoke-IdleTestNoopStep' }
                StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.Test')
            }

            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

            $plan.Steps[0].With.Value | Should -Be 'Enabled: True'
        }

        It 'throws when resolving to a hashtable' {
            $wfPath = Get-TemplateTestFixture 'template-hashtable'

            $req = New-IdleLifecycleRequest -LifecycleEvent 'Joiner' -DesiredState @{
                UserData = @{ Name = 'John'; Age = 30 }
            }
            $providers = @{
                StepRegistry = @{ 'IdLE.Step.Test' = 'Invoke-IdleTestNoopStep' }
                StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.Test')
            }

            { New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers } |
                Should -Throw -ExpectedMessage '*non-scalar value*'
        }

        It 'throws when resolving to an array' {
            $wfPath = Get-TemplateTestFixture 'template-array-value'

            $req = New-IdleLifecycleRequest -LifecycleEvent 'Joiner' -DesiredState @{
                Tags = @('tag1', 'tag2')
            }
            $providers = @{
                StepRegistry = @{ 'IdLE.Step.Test' = 'Invoke-IdleTestNoopStep' }
                StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.Test')
            }

            { New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers } |
                Should -Throw -ExpectedMessage '*non-scalar value*'
        }
    }
}

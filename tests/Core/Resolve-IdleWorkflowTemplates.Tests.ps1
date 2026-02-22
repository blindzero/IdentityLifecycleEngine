Set-StrictMode -Version Latest

BeforeAll {
    . (Join-Path (Split-Path -Path $PSScriptRoot -Parent) '_testHelpers.ps1')
    Import-IdleTestModule

    function global:Invoke-IdleTestNoopStep {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [ValidateNotNull()]
            [object] $Context,

            [Parameter(Mandatory)]
            [ValidateNotNull()]
            [object] $Step
        )

        return [pscustomobject]@{
            PSTypeName = 'IdLE.StepResult'
            Name       = [string]$Step.Name
            Type       = [string]$Step.Type
            Status     = 'Completed'
            Error      = $null
        }
    }

    $script:FixtureRoot = Join-Path $PSScriptRoot '..' 'fixtures/workflows/template-tests'

    function Get-TemplateTestFixture {
        param([string]$Name)
        return Join-Path $script:FixtureRoot "$Name.psd1"
    }
}

AfterAll {
    Remove-Item -Path 'Function:\Invoke-IdleTestNoopStep' -ErrorAction SilentlyContinue
}

Describe 'Template Substitution' {
    Context 'Single placeholder substitution' {
        It 'resolves a simple Request.Intent placeholder' {
            $wfPath = Get-TemplateTestFixture 'template-simple'

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner' -Intent @{
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

        It 'resolves Request.Intent placeholder' {
            $wfPath = Get-TemplateTestFixture 'template-intent'

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner' -Intent @{
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

        It 'resolves Request.Context placeholder' {
            $wfPath = Get-TemplateTestFixture 'template-context'

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner' -Context @{
                Identity = @{ ObjectId = 'obj-abc-123' }
            }
            $providers = @{
                StepRegistry = @{
                    'IdLE.Step.Test' = 'Invoke-IdleTestNoopStep'
                }
                StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.Test')
            }

            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

            $plan.Steps[0].With.ObjectId | Should -Be 'obj-abc-123'
        }
    }

    Context 'Multiple placeholders in one string' {
        It 'resolves multiple Intent placeholders in a single string' {
            $wfPath = Get-TemplateTestFixture 'template-multiple'

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner' -Intent @{
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

        It 'resolves multiple Context placeholders in a single string' {
            $wfPath = Get-TemplateTestFixture 'template-context-multiple'

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner' -Context @{
                Identity = @{
                    DisplayName = 'Jane Smith'
                    ObjectId    = 'abc-123'
                }
            }
            $providers = @{
                StepRegistry = @{
                    'IdLE.Step.Test' = 'Invoke-IdleTestNoopStep'
                }
                StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.Test')
            }

            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

            $plan.Steps[0].With.Message | Should -Be 'Identity Jane Smith (abc-123) loaded.'
        }
    }

    Context 'Nested hashtable and array substitution' {
        It 'resolves Intent templates in nested hashtables' {
            $wfPath = Get-TemplateTestFixture 'template-nested-hash'

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner' -Intent @{
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

        It 'resolves Context templates in nested hashtables' {
            $wfPath = Get-TemplateTestFixture 'template-context-nested-hash'

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner' -Context @{
                Identity = @{
                    DisplayName = 'Alice Brown'
                    Mail        = 'alice.brown@example.com'
                }
            }
            $providers = @{
                StepRegistry = @{
                    'IdLE.Step.Test' = 'Invoke-IdleTestNoopStep'
                }
                StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.Test')
            }

            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

            $plan.Steps[0].With.Identity.Name | Should -Be 'Alice Brown'
            $plan.Steps[0].With.Identity.Email | Should -Be 'alice.brown@example.com'
        }

        It 'resolves templates in arrays' {
            $wfPath = Get-TemplateTestFixture 'template-array'

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner' -Intent @{
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

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner' -Intent @{ Name = 'Test' }
            $providers = @{
                StepRegistry = @{ 'IdLE.Step.Test' = 'Invoke-IdleTestNoopStep' }
                StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.Test')
            }

            { New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers } |
                Should -Throw -ExpectedMessage '*Unbalanced braces*'
        }

        It 'throws on unbalanced closing brace' {
            $wfPath = Get-TemplateTestFixture 'template-unbalanced-close'

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner' -Intent @{ Name = 'Test' }
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

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner' -Intent @{ UserName = 'Test' }
            $providers = @{
                StepRegistry = @{ 'IdLE.Step.Test' = 'Invoke-IdleTestNoopStep' }
                StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.Test')
            }

            { New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers } |
                Should -Throw -ExpectedMessage '*Invalid path pattern*'
        }

        It 'throws on path with special characters' {
            $wfPath = Get-TemplateTestFixture 'template-path-special'

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner' -Intent @{ UserName = 'Test' }
            $providers = @{
                StepRegistry = @{ 'IdLE.Step.Test' = 'Invoke-IdleTestNoopStep' }
                StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.Test')
            }

            { New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers } |
                Should -Throw -ExpectedMessage '*Invalid path pattern*'
        }
    }

    Context 'Missing path segments' {
        It 'throws when Intent path does not exist' {
            $wfPath = Get-TemplateTestFixture 'template-missing-path'

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner' -Intent @{ Name = 'Test' }
            $providers = @{
                StepRegistry = @{ 'IdLE.Step.Test' = 'Invoke-IdleTestNoopStep' }
                StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.Test')
            }

            { New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers } |
                Should -Throw -ExpectedMessage '*resolved to null or does not exist*'
        }

        It 'throws when Context path does not exist' {
            $wfPath = Get-TemplateTestFixture 'template-context-missing-path'

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner' -Context @{ Identity = @{ ObjectId = 'abc' } }
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

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner' -Intent @{ NullField = $null }
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

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner' -Intent @{ Name = 'Test' }
            $providers = @{
                StepRegistry = @{ 'IdLE.Step.Test' = 'Invoke-IdleTestNoopStep' }
                StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.Test')
            }

            { New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers } |
                Should -Throw -ExpectedMessage '*is not allowed*'
        }

        It 'throws when accessing Providers root' {
            $wfPath = Get-TemplateTestFixture 'template-providers-root'

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner' -Intent @{ Name = 'Test' }
            $providers = @{
                StepRegistry = @{ 'IdLE.Step.Test' = 'Invoke-IdleTestNoopStep' }
                StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.Test')
            }

            { New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers } |
                Should -Throw -ExpectedMessage '*is not allowed*'
        }

        It 'throws when accessing Workflow root' {
            $wfPath = Get-TemplateTestFixture 'template-workflow-root'

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner' -Intent @{ Name = 'Test' }
            $providers = @{
                StepRegistry = @{ 'IdLE.Step.Test' = 'Invoke-IdleTestNoopStep' }
                StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.Test')
            }

            { New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers } |
                Should -Throw -ExpectedMessage '*is not allowed*'
        }
    }

    Context 'Escaping' {
        It 'handles escaped opening braces' {
            $wfPath = Get-TemplateTestFixture 'template-escaped'

            $req = New-IdleRequest -LifecycleEvent 'Joiner' -Intent @{ Name = 'Test' }
            $providers = @{
                StepRegistry = @{ 'IdLE.Step.Test' = 'Invoke-IdleTestNoopStep' }
                StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.Test')
            }

            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

            $plan.Steps[0].With.Value | Should -Be 'Literal {{ braces here'
        }

        It 'handles escaped braces mixed with templates' {
            $wfPath = Get-TemplateTestFixture 'template-escaped-mixed'

            $req = New-IdleRequest -LifecycleEvent 'Joiner' -Intent @{ Name = 'TestName' }
            $providers = @{
                StepRegistry = @{ 'IdLE.Step.Test' = 'Invoke-IdleTestNoopStep' }
                StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.Test')
            }

            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

            $plan.Steps[0].With.Value | Should -Be 'Literal {{ and template TestName'
        }

        It 'treats backslash before {{ as a literal character (not an escape)' {
            $wfPath = Get-TemplateTestFixture 'template-backslash'

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner' -IdentityKeys @{ sAMAccountName = 'jdoe' }
            $providers = @{
                StepRegistry = @{ 'IdLE.Step.Test' = 'Invoke-IdleTestNoopStep' }
                StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.Test')
            }

            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

            $plan.Steps[0].With.IdentityKey | Should -Be 'DOMAIN\jdoe'
        }

        It 'escapes \{{ followed by an invalid (non-allowed) root — throws unbalanced braces, not path error' {
            # With the tight allowed-root lookahead, \{{InvalidRoot}} is escaped (placeholder replaces \{{)
            # leaving }} orphaned → "unbalanced braces" error, same as original code.
            # A loose lookahead would let this through to template parsing → wrong "path not allowed" error.
            $wfPath = Get-TemplateTestFixture 'template-escaped-invalid-root'

            $req = New-IdleRequest -LifecycleEvent 'Joiner' -Intent @{ Name = 'Test' }
            $providers = @{
                StepRegistry = @{ 'IdLE.Step.Test' = 'Invoke-IdleTestNoopStep' }
                StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.Test')
            }

            { New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers } |
                Should -Throw -ExpectedMessage '*Unbalanced braces*'
        }
    }

    Context 'OnFailureSteps template resolution' {
        It 'resolves templates in OnFailureSteps' {
            $wfPath = Get-TemplateTestFixture 'template-onfailure'

            $req = New-IdleRequest -LifecycleEvent 'Joiner' -Intent @{
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

            $req = New-IdleRequest -LifecycleEvent 'Joiner' -Intent @{ Name = 'Test' }
            $providers = @{
                StepRegistry = @{ 'IdLE.Step.Test' = 'Invoke-IdleTestNoopStep' }
                StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.Test')
            }

            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

            $plan.Steps[0].With.Event | Should -Be 'Joiner'
        }

        It 'allows Request.CorrelationId' {
            $wfPath = Get-TemplateTestFixture 'template-correlation-id'

            $req = New-IdleRequest -LifecycleEvent 'Joiner' -Intent @{ Name = 'Test' }
            $providers = @{
                StepRegistry = @{ 'IdLE.Step.Test' = 'Invoke-IdleTestNoopStep' }
                StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.Test')
            }

            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

            $plan.Steps[0].With.Id | Should -Be $req.CorrelationId
        }

        It 'allows Request.Actor' {
            $wfPath = Get-TemplateTestFixture 'template-actor'

            $req = New-IdleRequest -LifecycleEvent 'Joiner' -Intent @{ Name = 'Test' } -Actor 'admin@example.com'
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

            $req = New-IdleRequest -LifecycleEvent 'Joiner' -Intent @{ UserId = 12345 }
            $providers = @{
                StepRegistry = @{ 'IdLE.Step.Test' = 'Invoke-IdleTestNoopStep' }
                StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.Test')
            }

            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

            $plan.Steps[0].With.Value | Should -Be 'ID: 12345'
        }

        It 'resolves boolean types to strings' {
            $wfPath = Get-TemplateTestFixture 'template-boolean'

            $req = New-IdleRequest -LifecycleEvent 'Joiner' -Intent @{ IsEnabled = $true }
            $providers = @{
                StepRegistry = @{ 'IdLE.Step.Test' = 'Invoke-IdleTestNoopStep' }
                StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.Test')
            }

            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

            $plan.Steps[0].With.Value | Should -Be 'Enabled: True'
        }

        It 'throws when resolving to a hashtable' {
            $wfPath = Get-TemplateTestFixture 'template-hashtable'

            $req = New-IdleRequest -LifecycleEvent 'Joiner' -Intent @{
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

            $req = New-IdleRequest -LifecycleEvent 'Joiner' -Intent @{
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

    Context 'Type preservation for pure placeholders' {
        It 'preserves boolean false type for pure placeholder' {
            $wfPath = Get-TemplateTestFixture 'template-pure-boolean-false'

            $req = New-IdleRequest -LifecycleEvent 'Joiner' -Intent @{ Enabled = $false }
            $providers = @{
                StepRegistry = @{ 'IdLE.Step.Test' = 'Invoke-IdleTestNoopStep' }
                StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.Test')
            }

            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

            $plan.Steps[0].With.Enabled | Should -BeOfType [bool]
            $plan.Steps[0].With.Enabled | Should -BeFalse
            # Verify it's not the string "False"
            $plan.Steps[0].With.Enabled | Should -Not -BeOfType [string]
        }

        It 'preserves boolean true type for pure placeholder' {
            $wfPath = Get-TemplateTestFixture 'template-pure-boolean-true'

            $req = New-IdleRequest -LifecycleEvent 'Joiner' -Intent @{ IsActive = $true }
            $providers = @{
                StepRegistry = @{ 'IdLE.Step.Test' = 'Invoke-IdleTestNoopStep' }
                StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.Test')
            }

            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

            $plan.Steps[0].With.IsActive | Should -BeOfType [bool]
            $plan.Steps[0].With.IsActive | Should -BeTrue
        }

        It 'preserves integer type for pure placeholder' {
            $wfPath = Get-TemplateTestFixture 'template-pure-integer'

            $req = New-IdleRequest -LifecycleEvent 'Joiner' -Intent @{ UserId = 12345 }
            $providers = @{
                StepRegistry = @{ 'IdLE.Step.Test' = 'Invoke-IdleTestNoopStep' }
                StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.Test')
            }

            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

            $plan.Steps[0].With.UserId | Should -BeOfType [int]
            $plan.Steps[0].With.UserId | Should -Be 12345
        }

        It 'preserves datetime type for pure placeholder' {
            $wfPath = Get-TemplateTestFixture 'template-pure-datetime'

            $testDate = Get-Date '2026-01-15T10:00:00'
            $req = New-IdleRequest -LifecycleEvent 'Joiner' -Intent @{ StartDate = $testDate }
            $providers = @{
                StepRegistry = @{ 'IdLE.Step.Test' = 'Invoke-IdleTestNoopStep' }
                StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.Test')
            }

            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

            $plan.Steps[0].With.StartDate | Should -BeOfType [datetime]
            $plan.Steps[0].With.StartDate | Should -Be $testDate
        }

        It 'preserves guid type for pure placeholder' {
            $wfPath = Get-TemplateTestFixture 'template-pure-guid'

            $testGuid = [guid]::NewGuid()
            $req = New-IdleRequest -LifecycleEvent 'Joiner' -Intent @{ ObjectId = $testGuid }
            $providers = @{
                StepRegistry = @{ 'IdLE.Step.Test' = 'Invoke-IdleTestNoopStep' }
                StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.Test')
            }

            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

            $plan.Steps[0].With.ObjectId | Should -BeOfType [guid]
            $plan.Steps[0].With.ObjectId | Should -Be $testGuid
        }

        It 'converts to string for mixed template (string interpolation)' {
            $wfPath = Get-TemplateTestFixture 'template-mixed-boolean'

            $req = New-IdleRequest -LifecycleEvent 'Joiner' -Intent @{ Enabled = $false }
            $providers = @{
                StepRegistry = @{ 'IdLE.Step.Test' = 'Invoke-IdleTestNoopStep' }
                StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.Test')
            }

            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

            $plan.Steps[0].With.Message | Should -BeOfType [string]
            $plan.Steps[0].With.Message | Should -Be 'Account enabled: False'
        }
    }

    # Note: Security validation tests for ScriptBlock/PSCredential/SecureString are validated
    # through direct unit testing due to test harness limitations. The security checks
    # are applied regardless of pure/mixed template mode as verified by manual testing.
}


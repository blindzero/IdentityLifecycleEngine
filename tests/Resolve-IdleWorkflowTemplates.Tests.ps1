BeforeAll {
    . (Join-Path $PSScriptRoot '_testHelpers.ps1')
    Import-IdleTestModule
}

Describe 'Template Substitution' {
    Context 'Single placeholder substitution' {
        It 'resolves a simple Request.Input placeholder' {
            $wfPath = Join-Path -Path $TestDrive -ChildPath 'template-simple.psd1'
            Set-Content -Path $wfPath -Encoding UTF8 -Value @'
@{
  Name           = 'Template Test - Simple'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'TestStep'
      Type = 'IdLE.Step.Test'
      With = @{
        UserName = '{{Request.Input.UserPrincipalName}}'
      }
    }
  )
}
'@

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
            $wfPath = Join-Path -Path $TestDrive -ChildPath 'template-desiredstate.psd1'
            Set-Content -Path $wfPath -Encoding UTF8 -Value @'
@{
  Name           = 'Template Test - DesiredState'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'TestStep'
      Type = 'IdLE.Step.Test'
      With = @{
        Department = '{{Request.DesiredState.Department}}'
      }
    }
  )
}
'@

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
            $wfPath = Join-Path -Path $TestDrive -ChildPath 'template-multiple.psd1'
            Set-Content -Path $wfPath -Encoding UTF8 -Value @'
@{
  Name           = 'Template Test - Multiple'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'TestStep'
      Type = 'IdLE.Step.Test'
      With = @{
        Message = 'User {{Request.Input.DisplayName}} ({{Request.Input.UserPrincipalName}}) is joining.'
      }
    }
  )
}
'@

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
            $wfPath = Join-Path -Path $TestDrive -ChildPath 'template-nested-hash.psd1'
            Set-Content -Path $wfPath -Encoding UTF8 -Value @'
@{
  Name           = 'Template Test - Nested Hash'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'TestStep'
      Type = 'IdLE.Step.Test'
      With = @{
        User = @{
          Name  = '{{Request.Input.DisplayName}}'
          Email = '{{Request.Input.Mail}}'
        }
      }
    }
  )
}
'@

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
            $wfPath = Join-Path -Path $TestDrive -ChildPath 'template-array.psd1'
            Set-Content -Path $wfPath -Encoding UTF8 -Value @'
@{
  Name           = 'Template Test - Array'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'TestStep'
      Type = 'IdLE.Step.Test'
      With = @{
        Emails = @(
          '{{Request.Input.PrimaryEmail}}'
          '{{Request.Input.SecondaryEmail}}'
        )
      }
    }
  )
}
'@

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
            $wfPath = Join-Path -Path $TestDrive -ChildPath 'template-unbalanced-open.psd1'
            Set-Content -Path $wfPath -Encoding UTF8 -Value @'
@{
  Name           = 'Template Test - Unbalanced Open'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'TestStep'
      Type = 'IdLE.Step.Test'
      With = @{
        Value = '{{Request.Input.Name'
      }
    }
  )
}
'@

            $req = New-IdleLifecycleRequest -LifecycleEvent 'Joiner' -DesiredState @{ Name = 'Test' }
            $providers = @{
                StepRegistry = @{ 'IdLE.Step.Test' = 'Invoke-IdleTestNoopStep' }
                StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.Test')
            }

            { New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers } |
                Should -Throw -ExpectedMessage '*Unbalanced braces*'
        }

        It 'throws on unbalanced closing brace' {
            $wfPath = Join-Path -Path $TestDrive -ChildPath 'template-unbalanced-close.psd1'
            Set-Content -Path $wfPath -Encoding UTF8 -Value @'
@{
  Name           = 'Template Test - Unbalanced Close'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'TestStep'
      Type = 'IdLE.Step.Test'
      With = @{
        Value = 'Request.Input.Name}}'
      }
    }
  )
}
'@

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
            $wfPath = Join-Path -Path $TestDrive -ChildPath 'template-path-spaces.psd1'
            Set-Content -Path $wfPath -Encoding UTF8 -Value @'
@{
  Name           = 'Template Test - Path Spaces'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'TestStep'
      Type = 'IdLE.Step.Test'
      With = @{
        Value = '{{Request.Input.User Name}}'
      }
    }
  )
}
'@

            $req = New-IdleLifecycleRequest -LifecycleEvent 'Joiner' -DesiredState @{ UserName = 'Test' }
            $providers = @{
                StepRegistry = @{ 'IdLE.Step.Test' = 'Invoke-IdleTestNoopStep' }
                StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.Test')
            }

            { New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers } |
                Should -Throw -ExpectedMessage '*Invalid path pattern*'
        }

        It 'throws on path with special characters' {
            $wfPath = Join-Path -Path $TestDrive -ChildPath 'template-path-special.psd1'
            Set-Content -Path $wfPath -Encoding UTF8 -Value @'
@{
  Name           = 'Template Test - Path Special'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'TestStep'
      Type = 'IdLE.Step.Test'
      With = @{
        Value = '{{Request.Input.User@Name}}'
      }
    }
  )
}
'@

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
            $wfPath = Join-Path -Path $TestDrive -ChildPath 'template-missing-path.psd1'
            Set-Content -Path $wfPath -Encoding UTF8 -Value @'
@{
  Name           = 'Template Test - Missing Path'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'TestStep'
      Type = 'IdLE.Step.Test'
      With = @{
        Value = '{{Request.Input.NonExistent}}'
      }
    }
  )
}
'@

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
            $wfPath = Join-Path -Path $TestDrive -ChildPath 'template-null-value.psd1'
            Set-Content -Path $wfPath -Encoding UTF8 -Value @'
@{
  Name           = 'Template Test - Null Value'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'TestStep'
      Type = 'IdLE.Step.Test'
      With = @{
        Value = '{{Request.Input.NullField}}'
      }
    }
  )
}
'@

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
            $wfPath = Join-Path -Path $TestDrive -ChildPath 'template-plan-root.psd1'
            Set-Content -Path $wfPath -Encoding UTF8 -Value @'
@{
  Name           = 'Template Test - Plan Root'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'TestStep'
      Type = 'IdLE.Step.Test'
      With = @{
        Value = '{{Plan.WorkflowName}}'
      }
    }
  )
}
'@

            $req = New-IdleLifecycleRequest -LifecycleEvent 'Joiner' -DesiredState @{ Name = 'Test' }
            $providers = @{
                StepRegistry = @{ 'IdLE.Step.Test' = 'Invoke-IdleTestNoopStep' }
                StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.Test')
            }

            { New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers } |
                Should -Throw -ExpectedMessage '*is not allowed*'
        }

        It 'throws when accessing Providers root' {
            $wfPath = Join-Path -Path $TestDrive -ChildPath 'template-providers-root.psd1'
            Set-Content -Path $wfPath -Encoding UTF8 -Value @'
@{
  Name           = 'Template Test - Providers Root'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'TestStep'
      Type = 'IdLE.Step.Test'
      With = @{
        Value = '{{Providers.AuthSessionBroker}}'
      }
    }
  )
}
'@

            $req = New-IdleLifecycleRequest -LifecycleEvent 'Joiner' -DesiredState @{ Name = 'Test' }
            $providers = @{
                StepRegistry = @{ 'IdLE.Step.Test' = 'Invoke-IdleTestNoopStep' }
                StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.Test')
            }

            { New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers } |
                Should -Throw -ExpectedMessage '*is not allowed*'
        }

        It 'throws when accessing Workflow root' {
            $wfPath = Join-Path -Path $TestDrive -ChildPath 'template-workflow-root.psd1'
            Set-Content -Path $wfPath -Encoding UTF8 -Value @'
@{
  Name           = 'Template Test - Workflow Root'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'TestStep'
      Type = 'IdLE.Step.Test'
      With = @{
        Value = '{{Workflow.Name}}'
      }
    }
  )
}
'@

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
            $wfPath = Join-Path -Path $TestDrive -ChildPath 'template-input-exists.psd1'
            Set-Content -Path $wfPath -Encoding UTF8 -Value @'
@{
  Name           = 'Template Test - Input Exists'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'TestStep'
      Type = 'IdLE.Step.Test'
      With = @{
        Value = '{{Request.Input.Name}}'
      }
    }
  )
}
'@

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
            $wfPath = Join-Path -Path $TestDrive -ChildPath 'template-input-alias.psd1'
            Set-Content -Path $wfPath -Encoding UTF8 -Value @'
@{
  Name           = 'Template Test - Input Alias'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'TestStep'
      Type = 'IdLE.Step.Test'
      With = @{
        Value = '{{Request.Input.Name}}'
      }
    }
  )
}
'@

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
            $wfPath = Join-Path -Path $TestDrive -ChildPath 'template-escaped.psd1'
            Set-Content -Path $wfPath -Encoding UTF8 -Value @'
@{
  Name           = 'Template Test - Escaped'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'TestStep'
      Type = 'IdLE.Step.Test'
      With = @{
        Value = 'Literal \{{ braces here'
      }
    }
  )
}
'@

            $req = New-IdleLifecycleRequest -LifecycleEvent 'Joiner' -DesiredState @{ Name = 'Test' }
            $providers = @{
                StepRegistry = @{ 'IdLE.Step.Test' = 'Invoke-IdleTestNoopStep' }
                StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.Test')
            }

            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

            $plan.Steps[0].With.Value | Should -Be 'Literal {{ braces here'
        }

        It 'handles escaped braces mixed with templates' {
            $wfPath = Join-Path -Path $TestDrive -ChildPath 'template-escaped-mixed.psd1'
            Set-Content -Path $wfPath -Encoding UTF8 -Value @'
@{
  Name           = 'Template Test - Escaped Mixed'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'TestStep'
      Type = 'IdLE.Step.Test'
      With = @{
        Value = 'Literal \{{ and template {{Request.Input.Name}}'
      }
    }
  )
}
'@

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
            $wfPath = Join-Path -Path $TestDrive -ChildPath 'template-onfailure.psd1'
            Set-Content -Path $wfPath -Encoding UTF8 -Value @'
@{
  Name           = 'Template Test - OnFailureSteps'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'MainStep'
      Type = 'IdLE.Step.Test'
      With = @{
        Value = '{{Request.Input.Name}}'
      }
    }
  )
  OnFailureSteps = @(
    @{
      Name = 'FailureHandler'
      Type = 'IdLE.Step.Test'
      With = @{
        ErrorMessage = 'Failed for user {{Request.Input.UserPrincipalName}}'
      }
    }
  )
}
'@

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
            $wfPath = Join-Path -Path $TestDrive -ChildPath 'template-lifecycle-event.psd1'
            Set-Content -Path $wfPath -Encoding UTF8 -Value @'
@{
  Name           = 'Template Test - LifecycleEvent'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'TestStep'
      Type = 'IdLE.Step.Test'
      With = @{
        Event = '{{Request.LifecycleEvent}}'
      }
    }
  )
}
'@

            $req = New-IdleLifecycleRequest -LifecycleEvent 'Joiner' -DesiredState @{ Name = 'Test' }
            $providers = @{
                StepRegistry = @{ 'IdLE.Step.Test' = 'Invoke-IdleTestNoopStep' }
                StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.Test')
            }

            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

            $plan.Steps[0].With.Event | Should -Be 'Joiner'
        }

        It 'allows Request.CorrelationId' {
            $wfPath = Join-Path -Path $TestDrive -ChildPath 'template-correlation-id.psd1'
            Set-Content -Path $wfPath -Encoding UTF8 -Value @'
@{
  Name           = 'Template Test - CorrelationId'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'TestStep'
      Type = 'IdLE.Step.Test'
      With = @{
        Id = '{{Request.CorrelationId}}'
      }
    }
  )
}
'@

            $req = New-IdleLifecycleRequest -LifecycleEvent 'Joiner' -DesiredState @{ Name = 'Test' }
            $providers = @{
                StepRegistry = @{ 'IdLE.Step.Test' = 'Invoke-IdleTestNoopStep' }
                StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.Test')
            }

            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

            $plan.Steps[0].With.Id | Should -Be $req.CorrelationId
        }

        It 'allows Request.Actor' {
            $wfPath = Join-Path -Path $TestDrive -ChildPath 'template-actor.psd1'
            Set-Content -Path $wfPath -Encoding UTF8 -Value @'
@{
  Name           = 'Template Test - Actor'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'TestStep'
      Type = 'IdLE.Step.Test'
      With = @{
        ActorName = '{{Request.Actor}}'
      }
    }
  )
}
'@

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
            $wfPath = Join-Path -Path $TestDrive -ChildPath 'template-numeric.psd1'
            Set-Content -Path $wfPath -Encoding UTF8 -Value @'
@{
  Name           = 'Template Test - Numeric'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'TestStep'
      Type = 'IdLE.Step.Test'
      With = @{
        Value = 'ID: {{Request.Input.UserId}}'
      }
    }
  )
}
'@

            $req = New-IdleLifecycleRequest -LifecycleEvent 'Joiner' -DesiredState @{ UserId = 12345 }
            $providers = @{
                StepRegistry = @{ 'IdLE.Step.Test' = 'Invoke-IdleTestNoopStep' }
                StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.Test')
            }

            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

            $plan.Steps[0].With.Value | Should -Be 'ID: 12345'
        }

        It 'resolves boolean types to strings' {
            $wfPath = Join-Path -Path $TestDrive -ChildPath 'template-boolean.psd1'
            Set-Content -Path $wfPath -Encoding UTF8 -Value @'
@{
  Name           = 'Template Test - Boolean'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'TestStep'
      Type = 'IdLE.Step.Test'
      With = @{
        Value = 'Enabled: {{Request.Input.IsEnabled}}'
      }
    }
  )
}
'@

            $req = New-IdleLifecycleRequest -LifecycleEvent 'Joiner' -DesiredState @{ IsEnabled = $true }
            $providers = @{
                StepRegistry = @{ 'IdLE.Step.Test' = 'Invoke-IdleTestNoopStep' }
                StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.Test')
            }

            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

            $plan.Steps[0].With.Value | Should -Be 'Enabled: True'
        }

        It 'throws when resolving to a hashtable' {
            $wfPath = Join-Path -Path $TestDrive -ChildPath 'template-hashtable.psd1'
            Set-Content -Path $wfPath -Encoding UTF8 -Value @'
@{
  Name           = 'Template Test - Hashtable'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'TestStep'
      Type = 'IdLE.Step.Test'
      With = @{
        Value = '{{Request.Input.UserData}}'
      }
    }
  )
}
'@

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
            $wfPath = Join-Path -Path $TestDrive -ChildPath 'template-array-value.psd1'
            Set-Content -Path $wfPath -Encoding UTF8 -Value @'
@{
  Name           = 'Template Test - Array Value'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'TestStep'
      Type = 'IdLE.Step.Test'
      With = @{
        Value = '{{Request.Input.Tags}}'
      }
    }
  )
}
'@

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

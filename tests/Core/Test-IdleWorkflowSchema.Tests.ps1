Set-StrictMode -Version Latest

BeforeDiscovery {
    . (Join-Path (Split-Path -Path $PSScriptRoot -Parent) '_testHelpers.ps1')
    Import-IdleTestModule
}

Describe 'Workflow schema validation - Condition/Precondition DSL parity' {
    InModuleScope 'IdLE.Core' {
        It 'rejects invalid Condition DSL nodes at definition validation time' {
            $workflow = @{
                Name           = 'Condition Validation'
                LifecycleEvent = 'Joiner'
                Steps          = @(
                    @{
                        Name      = 'InvalidCondition'
                        Type      = 'IdLE.Step.Noop'
                        Condition = @{ Foo = @{ Path = 'Plan.LifecycleEvent'; Value = 'Joiner' } }
                    }
                )
            }

            $errors = Test-IdleWorkflowSchema -Workflow $workflow
            @($errors | Where-Object { $_ -like "*Steps[0].Condition*invalid condition schema*" }).Count | Should -BeGreaterThan 0
        }


        It 'rejects invalid Condition DSL nodes in OnFailureSteps at definition validation time' {
            $workflow = @{
                Name           = 'Condition Validation'
                LifecycleEvent = 'Joiner'
                Steps          = @(
                    @{ Name = 'Primary'; Type = 'IdLE.Step.Noop' }
                )
                OnFailureSteps = @(
                    @{
                        Name      = 'InvalidOnFailureCondition'
                        Type      = 'IdLE.Step.Noop'
                        Condition = @{ Foo = @{ Path = 'Plan.LifecycleEvent'; Value = 'Joiner' } }
                    }
                )
            }

            $errors = Test-IdleWorkflowSchema -Workflow $workflow
            @($errors | Where-Object { $_ -like "*OnFailureSteps[0].Condition*invalid condition schema*" }).Count | Should -BeGreaterThan 0
        }
        It 'rejects invalid Preconditions DSL nodes at definition validation time' {
            $workflow = @{
                Name           = 'Precondition Validation'
                LifecycleEvent = 'Joiner'
                Steps          = @(
                    @{
                        Name          = 'InvalidPrecondition'
                        Type          = 'IdLE.Step.Noop'
                        Preconditions = @(
                            @{ Foo = @{ Path = 'Plan.LifecycleEvent'; Value = 'Joiner' } }
                        )
                    }
                )
            }

            $errors = Test-IdleWorkflowSchema -Workflow $workflow
            @($errors | Where-Object { $_ -like "*Steps[0].Preconditions[0]*invalid condition schema*" }).Count | Should -BeGreaterThan 0
        }


        It 'accepts deprecated singular Precondition alias with the same condition DSL' {
            $workflow = @{
                Name           = 'Singular Precondition Alias'
                LifecycleEvent = 'Joiner'
                Steps          = @(
                    @{
                        Name         = 'SingularAlias'
                        Type         = 'IdLE.Step.Noop'
                        Precondition = @{ Exists = 'Request.IdentityKeys.EmployeeId' }
                    }
                )
            }

            $errors = Test-IdleWorkflowSchema -Workflow $workflow
            $errors.Count | Should -Be 0
        }

        It 'rejects defining both Preconditions and Precondition on the same step' {
            $workflow = @{
                Name           = 'Conflicting Precondition Keys'
                LifecycleEvent = 'Joiner'
                Steps          = @(
                    @{
                        Name          = 'ConflictingKeys'
                        Type          = 'IdLE.Step.Noop'
                        Precondition  = @{ Exists = 'Request.IdentityKeys.EmployeeId' }
                        Preconditions = @(
                            @{ Exists = 'Request.IdentityKeys.EmployeeId' }
                        )
                    }
                )
            }

            $errors = Test-IdleWorkflowSchema -Workflow $workflow
            @($errors | Where-Object { $_ -like "*must not define both 'Preconditions' and deprecated alias 'Precondition'*" }).Count | Should -BeGreaterThan 0
        }
        It 'accepts valid preconditions using the same condition DSL' {
            $workflow = @{
                Name           = 'Precondition Validation'
                LifecycleEvent = 'Joiner'
                Steps          = @(
                    @{
                        Name          = 'ValidPrecondition'
                        Type          = 'IdLE.Step.Noop'
                        Condition     = @{ Equals = @{ Path = 'Plan.LifecycleEvent'; Value = 'Joiner' } }
                        Preconditions = @(
                            @{ Exists = @{ Path = 'Request.IdentityKeys.EmployeeId' } }
                            @{ In = @{ Path = 'Plan.LifecycleEvent'; Values = @('Joiner', 'Mover') } }
                        )
                    }
                )
            }

            $errors = Test-IdleWorkflowSchema -Workflow $workflow
            $errors.Count | Should -Be 0
        }
    }
}

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
            @($errors | Where-Object { $_ -like "*Steps``[0``].Condition*invalid condition schema*" }).Count | Should -BeGreaterThan 0
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
            @($errors | Where-Object { $_ -like "*OnFailureSteps``[0``].Condition*invalid condition schema*" }).Count | Should -BeGreaterThan 0
        }

        It 'rejects invalid Precondition DSL node at definition validation time' {
            $workflow = @{
                Name           = 'Precondition Validation'
                LifecycleEvent = 'Joiner'
                Steps          = @(
                    @{
                        Name         = 'InvalidPrecondition'
                        Type         = 'IdLE.Step.Noop'
                        Precondition = @{ Foo = @{ Path = 'Plan.LifecycleEvent'; Value = 'Joiner' } }
                    }
                )
            }

            $errors = Test-IdleWorkflowSchema -Workflow $workflow
            @($errors | Where-Object { $_ -like "*Steps``[0``].Precondition*invalid condition schema*" }).Count | Should -BeGreaterThan 0
        }

        It 'accepts valid precondition using the same condition DSL' {
            $workflow = @{
                Name           = 'Precondition Validation'
                LifecycleEvent = 'Joiner'
                Steps          = @(
                    @{
                        Name         = 'ValidPrecondition'
                        Type         = 'IdLE.Step.Noop'
                        Condition    = @{ Equals = @{ Path = 'Plan.LifecycleEvent'; Value = 'Joiner' } }
                        Precondition = @{
                            All = @(
                                @{ Exists = @{ Path = 'Request.IdentityKeys.EmployeeId' } }
                                @{ In = @{ Path = 'Plan.LifecycleEvent'; Values = @('Joiner', 'Mover') } }
                            )
                        }
                    }
                )
            }

            $errors = Test-IdleWorkflowSchema -Workflow $workflow
            @($errors).Count | Should -Be 0
        }
    }
}

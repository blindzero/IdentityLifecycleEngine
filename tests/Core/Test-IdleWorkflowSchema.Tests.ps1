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

Describe 'Workflow schema validation - ContextResolvers' {
    InModuleScope 'IdLE.Core' {
        It 'rejects root-level Provider key in a resolver entry (must use With.Provider)' {
            $workflow = @{
                Name             = 'Root Provider Rejected'
                LifecycleEvent   = 'Joiner'
                ContextResolvers = @(
                    @{
                        Capability = 'IdLE.Entitlement.List'
                        Provider   = 'Identity'
                        With       = @{ IdentityKey = 'user1' }
                    }
                )
                Steps            = @(
                    @{ Name = 'Step1'; Type = 'IdLE.Step.Noop' }
                )
            }

            $errors = Test-IdleWorkflowSchema -Workflow $workflow
            @($errors | Where-Object { $_ -like "*Unknown key*Provider*" }).Count | Should -BeGreaterThan 0
        }

        It 'rejects With.Provider as empty string' {
            $workflow = @{
                Name             = 'With.Provider Empty'
                LifecycleEvent   = 'Joiner'
                ContextResolvers = @(
                    @{
                        Capability = 'IdLE.Entitlement.List'
                        With       = @{ IdentityKey = 'user1'; Provider = '' }
                    }
                )
                Steps            = @(
                    @{ Name = 'Step1'; Type = 'IdLE.Step.Noop' }
                )
            }

            $errors = Test-IdleWorkflowSchema -Workflow $workflow
            @($errors | Where-Object { $_ -like "*With.Provider*must not be an empty string*" }).Count | Should -BeGreaterThan 0
        }

        It 'rejects With.AuthSessionOptions as a non-hashtable' {
            $workflow = @{
                Name             = 'With.AuthSessionOptions Invalid'
                LifecycleEvent   = 'Joiner'
                ContextResolvers = @(
                    @{
                        Capability = 'IdLE.Entitlement.List'
                        With       = @{ IdentityKey = 'user1'; AuthSessionName = 'Tier0'; AuthSessionOptions = 'not-a-hashtable' }
                    }
                )
                Steps            = @(
                    @{ Name = 'Step1'; Type = 'IdLE.Step.Noop' }
                )
            }

            $errors = Test-IdleWorkflowSchema -Workflow $workflow
            @($errors | Where-Object { $_ -like "*With.AuthSessionOptions*must be a hashtable*" }).Count | Should -BeGreaterThan 0
        }

        It 'accepts a valid resolver with With.Provider and With.AuthSessionOptions' {
            $workflow = @{
                Name             = 'Valid Resolver With.Provider'
                LifecycleEvent   = 'Joiner'
                ContextResolvers = @(
                    @{
                        Capability = 'IdLE.Entitlement.List'
                        With       = @{
                            IdentityKey        = 'user1'
                            Provider           = 'Identity'
                            AuthSessionName    = 'Tier0'
                            AuthSessionOptions = @{ Role = 'Tier0' }
                        }
                    }
                )
                Steps            = @(
                    @{ Name = 'Step1'; Type = 'IdLE.Step.Noop' }
                )
            }

            $errors = Test-IdleWorkflowSchema -Workflow $workflow
            @($errors).Count | Should -Be 0
        }
    }
}

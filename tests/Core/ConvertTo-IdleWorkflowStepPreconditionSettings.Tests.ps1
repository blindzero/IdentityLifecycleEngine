Set-StrictMode -Version Latest

BeforeDiscovery {
    . (Join-Path (Split-Path -Path $PSScriptRoot -Parent) '_testHelpers.ps1')
    Import-IdleTestModule
}

Describe 'ConvertTo-IdleWorkflowStepPreconditionSettings' {
    InModuleScope 'IdLE.Core' {
        It 'returns null values when the step does not define precondition settings' {
            $step = @{ Name = 'Noop'; Type = 'IdLE.Step.Noop' }

            $planningContext = @{ Plan = @{ LifecycleEvent = 'Joiner' }; Request = @{ IdentityKeys = @{}; Intent = @{}; Context = @{} } }
            $result = ConvertTo-IdleWorkflowStepPreconditionSettings -Step $step -StepName 'Noop' -PlanningContext $planningContext

            $result.Precondition | Should -BeNullOrEmpty
            $result.OnPreconditionFalse | Should -BeNullOrEmpty
            $result.PreconditionEvent | Should -BeNullOrEmpty
        }

        It 'normalizes valid precondition settings and deep-copies the data' {
            $step = @{
                Name                = 'GuardedStep'
                Type                = 'IdLE.Step.Noop'
                Precondition        = @{ Equals = @{ Path = 'Plan.LifecycleEvent'; Value = 'Joiner' } }
                OnPreconditionFalse = 'Continue'
                PreconditionEvent   = @{
                    Type    = 'ManualActionRequired'
                    Message = 'Operator action needed'
                    Data    = @{ Ticket = 'INC-1234' }
                }
            }

            $planningContext = @{ Plan = @{ LifecycleEvent = 'Joiner' }; Request = @{ IdentityKeys = @{}; Intent = @{}; Context = @{} } }
            $result = ConvertTo-IdleWorkflowStepPreconditionSettings -Step $step -StepName 'GuardedStep' -PlanningContext $planningContext

            $result.Precondition.Equals.Path | Should -Be 'Plan.LifecycleEvent'
            $result.OnPreconditionFalse | Should -Be 'Continue'
            $result.PreconditionEvent.Type | Should -Be 'ManualActionRequired'
            $result.PreconditionEvent.Data.Ticket | Should -Be 'INC-1234'

            # Verify deep-copy behavior.
            $step.PreconditionEvent.Data.Ticket = 'CHANGED'
            $result.PreconditionEvent.Data.Ticket | Should -Be 'INC-1234'
        }

        It 'throws when precondition path does not exist in planning context' {
            $step = @{
                Name         = 'MissingPath'
                Type         = 'IdLE.Step.Noop'
                Precondition = @{ Exists = 'Request.Context.OffboardingDate' }
            }

            $planningContext = @{ Plan = @{ LifecycleEvent = 'Joiner' }; Request = @{ IdentityKeys = @{}; Intent = @{}; Context = @{} } }
            { ConvertTo-IdleWorkflowStepPreconditionSettings -Step $step -StepName 'MissingPath' -PlanningContext $planningContext } | Should -Throw
        }

        It 'throws when OnPreconditionFalse has an invalid value' {
            $step = @{
                Name                = 'InvalidPolicy'
                Type                = 'IdLE.Step.Noop'
                OnPreconditionFalse = 'StopAll'
            }

            $planningContext = @{ Plan = @{ LifecycleEvent = 'Joiner' }; Request = @{ IdentityKeys = @{}; Intent = @{}; Context = @{} } }
            { ConvertTo-IdleWorkflowStepPreconditionSettings -Step $step -StepName 'InvalidPolicy' -PlanningContext $planningContext } | Should -Throw
        }
    }
}

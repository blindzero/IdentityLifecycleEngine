Set-StrictMode -Version Latest

BeforeDiscovery {
    . (Join-Path (Split-Path -Path $PSScriptRoot -Parent) '_testHelpers.ps1')
    Import-IdleTestModule
}

Describe 'ConvertTo-IdleWorkflowStepPreconditionSettings' {
    InModuleScope 'IdLE.Core' {
        It 'returns null values when the step does not define precondition settings' {
            $step = @{ Name = 'Noop'; Type = 'IdLE.Step.Noop' }

            $result = ConvertTo-IdleWorkflowStepPreconditionSettings -Step $step -StepName 'Noop'

            $result.Preconditions | Should -BeNullOrEmpty
            $result.OnPreconditionFalse | Should -BeNullOrEmpty
            $result.PreconditionEvent | Should -BeNullOrEmpty
        }

        It 'normalizes valid precondition settings and deep-copies the data' {
            $step = @{
                Name                = 'GuardedStep'
                Type                = 'IdLE.Step.Noop'
                Preconditions       = @(
                    @{ Equals = @{ Path = 'Plan.LifecycleEvent'; Value = 'Joiner' } }
                )
                OnPreconditionFalse = 'Continue'
                PreconditionEvent   = @{
                    Type    = 'ManualActionRequired'
                    Message = 'Operator action needed'
                    Data    = @{ Ticket = 'INC-1234' }
                }
            }

            $result = ConvertTo-IdleWorkflowStepPreconditionSettings -Step $step -StepName 'GuardedStep'

            $result.Preconditions.Count | Should -Be 1
            $result.OnPreconditionFalse | Should -Be 'Continue'
            $result.PreconditionEvent.Type | Should -Be 'ManualActionRequired'
            $result.PreconditionEvent.Data.Ticket | Should -Be 'INC-1234'

            # Verify deep-copy behavior.
            $step.PreconditionEvent.Data.Ticket = 'CHANGED'
            $result.PreconditionEvent.Data.Ticket | Should -Be 'INC-1234'
        }

        It 'throws when OnPreconditionFalse has an invalid value' {
            $step = @{
                Name                = 'InvalidPolicy'
                Type                = 'IdLE.Step.Noop'
                OnPreconditionFalse = 'StopAll'
            }

            { ConvertTo-IdleWorkflowStepPreconditionSettings -Step $step -StepName 'InvalidPolicy' } | Should -Throw
        }
    }
}

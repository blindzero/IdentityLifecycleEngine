Set-StrictMode -Version Latest

BeforeAll {
    . (Join-Path (Split-Path -Path $PSScriptRoot -Parent) '_testHelpers.ps1')
    Import-IdleTestModule
    $script:FixturesPath = Join-Path $PSScriptRoot '..' 'fixtures/workflows/preconditions'

    function global:Invoke-IdlePreconditionTestNoopStep {
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

    function global:Invoke-IdlePreconditionTestSecondStep {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [ValidateNotNull()]
            [object] $Context,

            [Parameter(Mandatory)]
            [ValidateNotNull()]
            [object] $Step
        )

        $Context.EventSink.WriteEvent('SecondStepRan', 'Second step executed', $Step.Name, @{ StepType = $Step.Type })

        return [pscustomobject]@{
            PSTypeName = 'IdLE.StepResult'
            Name       = [string]$Step.Name
            Type       = [string]$Step.Type
            Status     = 'Completed'
            Error      = $null
        }
    }

    function global:Invoke-IdlePreconditionTestOnFailureStep {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [ValidateNotNull()]
            [object] $Context,

            [Parameter(Mandatory)]
            [ValidateNotNull()]
            [object] $Step
        )

        $Context.EventSink.WriteEvent('OnFailureRan', 'OnFailure step executed', $Step.Name, @{ StepType = $Step.Type })

        return [pscustomobject]@{
            PSTypeName = 'IdLE.StepResult'
            Name       = [string]$Step.Name
            Type       = [string]$Step.Type
            Status     = 'Completed'
            Error      = $null
        }
    }
}

AfterAll {
    Remove-Item -Path 'Function:\Invoke-IdlePreconditionTestNoopStep' -ErrorAction SilentlyContinue
    Remove-Item -Path 'Function:\Invoke-IdlePreconditionTestSecondStep' -ErrorAction SilentlyContinue
    Remove-Item -Path 'Function:\Invoke-IdlePreconditionTestOnFailureStep' -ErrorAction SilentlyContinue
}

Describe 'Invoke-IdlePlan - Runtime Preconditions' {

    Context 'Step without preconditions' {
            It 'behaves exactly as before (no preconditions = no change)' {
                $wfPath   = Join-Path -Path $script:FixturesPath -ChildPath 'no-preconditions.psd1'
                $req      = New-IdleRequest -LifecycleEvent 'Joiner'
                $plan     = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers @{ StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.NoPrecondition') }
                $providers = @{
                    StepRegistry = @{ 'IdLE.Step.NoPrecondition' = 'Invoke-IdlePreconditionTestNoopStep' }
                    StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.NoPrecondition')
                }

                $result = Invoke-IdlePlan -Plan $plan -Providers $providers

                $result.Status | Should -Be 'Completed'
                $result.Steps[0].Status | Should -Be 'Completed'
                @($result.Events | Where-Object Type -eq 'StepPreconditionFailed').Count | Should -Be 0
            }
        }

        Context 'Passing preconditions' {
            It 'executes the step when all preconditions pass' {
                $wfPath   = Join-Path -Path $script:FixturesPath -ChildPath 'passing.psd1'
                $req      = New-IdleRequest -LifecycleEvent 'Leaver'
                $plan     = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers @{ StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.PassingPrecondition') }
                $providers = @{
                    StepRegistry = @{ 'IdLE.Step.PassingPrecondition' = 'Invoke-IdlePreconditionTestNoopStep' }
                    StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.PassingPrecondition')
                }

                $result = Invoke-IdlePlan -Plan $plan -Providers $providers

                $result.Status | Should -Be 'Completed'
                $result.Steps[0].Status | Should -Be 'Completed'
                @($result.Events | Where-Object Type -eq 'StepPreconditionFailed').Count | Should -Be 0
            }
        }

        Context 'Failing precondition - Blocked (default)' {
            It 'produces Blocked step result and stops execution when precondition fails' {
                $wfPath   = Join-Path -Path $script:FixturesPath -ChildPath 'blocked.psd1'
                $req      = New-IdleRequest -LifecycleEvent 'Leaver'
                $plan     = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers @{ StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.BlockedPrecondition', 'IdLE.Step.SecondStep') }
                $providers = @{
                    StepRegistry = @{
                        'IdLE.Step.BlockedPrecondition' = 'Invoke-IdlePreconditionTestNoopStep'
                        'IdLE.Step.SecondStep'          = 'Invoke-IdlePreconditionTestSecondStep'
                    }
                    StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.BlockedPrecondition', 'IdLE.Step.SecondStep')
                }

                $result = Invoke-IdlePlan -Plan $plan -Providers $providers

                $result.Status | Should -Be 'Blocked'
                $result.Steps.Count | Should -Be 1
                $result.Steps[0].Name   | Should -Be 'Step1'
                $result.Steps[0].Status | Should -Be 'Blocked'
                @($result.Events | Where-Object Type -eq 'StepPreconditionFailed').Count | Should -Be 1
                @($result.Events | Where-Object Type -eq 'SecondStepRan').Count | Should -Be 0
            }

            It 'uses Blocked as the default when OnPreconditionFalse is omitted' {
                $wfPath   = Join-Path -Path $script:FixturesPath -ChildPath 'blocked-default.psd1'
                $req      = New-IdleRequest -LifecycleEvent 'Leaver'
                $plan     = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers @{ StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.BlockedDefault') }
                $providers = @{
                    StepRegistry = @{ 'IdLE.Step.BlockedDefault' = 'Invoke-IdlePreconditionTestNoopStep' }
                    StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.BlockedDefault')
                }

                $result = Invoke-IdlePlan -Plan $plan -Providers $providers

                $result.Status | Should -Be 'Blocked'
                $result.Steps[0].Status | Should -Be 'Blocked'
            }
        }

        Context 'Failing precondition - Fail' {
            It 'produces Failed step result and stops execution when OnPreconditionFalse=Fail' {
                $wfPath   = Join-Path -Path $script:FixturesPath -ChildPath 'fail.psd1'
                $req      = New-IdleRequest -LifecycleEvent 'Leaver'
                $plan     = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers @{ StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.FailPrecondition', 'IdLE.Step.SecondStep') }
                $providers = @{
                    StepRegistry = @{
                        'IdLE.Step.FailPrecondition' = 'Invoke-IdlePreconditionTestNoopStep'
                        'IdLE.Step.SecondStep'       = 'Invoke-IdlePreconditionTestSecondStep'
                    }
                    StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.FailPrecondition', 'IdLE.Step.SecondStep')
                }

                $result = Invoke-IdlePlan -Plan $plan -Providers $providers

                $result.Status | Should -Be 'Failed'
                $result.Steps.Count | Should -Be 1
                $result.Steps[0].Status | Should -Be 'Failed'
                $result.Steps[0].Error  | Should -Not -BeNullOrEmpty
                @($result.Events | Where-Object Type -eq 'StepPreconditionFailed').Count | Should -Be 1
                @($result.Events | Where-Object Type -eq 'SecondStepRan').Count | Should -Be 0
            }
        }

        Context 'Failing precondition - Continue' {
            It 'emits events, marks step as PreconditionSkipped, and continues execution of subsequent steps' {
                $wfPath   = Join-Path -Path $script:FixturesPath -ChildPath 'continue.psd1'
                $req      = New-IdleRequest -LifecycleEvent 'Leaver'
                $plan     = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers @{ StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.ContinuePrecondition', 'IdLE.Step.SecondStep') }
                $providers = @{
                    StepRegistry = @{
                        'IdLE.Step.ContinuePrecondition' = 'Invoke-IdlePreconditionTestNoopStep'
                        'IdLE.Step.SecondStep'           = 'Invoke-IdlePreconditionTestSecondStep'
                    }
                    StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.ContinuePrecondition', 'IdLE.Step.SecondStep')
                }

                $result = Invoke-IdlePlan -Plan $plan -Providers $providers

                # Overall run completes successfully
                $result.Status | Should -Be 'Completed'
                # Step1 is skipped, Step2 runs
                $result.Steps.Count | Should -Be 2
                $result.Steps[0].Name   | Should -Be 'Step1'
                $result.Steps[0].Status | Should -Be 'PreconditionSkipped'
                $result.Steps[1].Name   | Should -Be 'Step2'
                $result.Steps[1].Status | Should -Be 'Completed'
                # Engine event is emitted for observability
                @($result.Events | Where-Object Type -eq 'StepPreconditionFailed').Count | Should -Be 1
                # Subsequent step ran
                @($result.Events | Where-Object Type -eq 'SecondStepRan').Count | Should -Be 1
            }

            It 'emits PreconditionEvent when Continue mode is used' {
                $wfPath   = Join-Path -Path $script:FixturesPath -ChildPath 'continue-event.psd1'
                $req      = New-IdleRequest -LifecycleEvent 'Leaver'
                $plan     = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers @{ StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.ContinuePreconditionEvent') }
                $providers = @{
                    StepRegistry = @{ 'IdLE.Step.ContinuePreconditionEvent' = 'Invoke-IdlePreconditionTestNoopStep' }
                    StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.ContinuePreconditionEvent')
                }

                $result = Invoke-IdlePlan -Plan $plan -Providers $providers

                $result.Status | Should -Be 'Completed'
                $result.Steps[0].Status | Should -Be 'PreconditionSkipped'
                ($result.Events | Where-Object Type -eq 'PolicyAdvisory').Message | Should -Be 'Step skipped due to policy advisory'
            }
        }

        Context 'Blocked does not trigger OnFailureSteps' {
            It 'does not run OnFailureSteps when a step is Blocked' {
                $wfPath   = Join-Path -Path $script:FixturesPath -ChildPath 'blocked-no-onfailure.psd1'
                $req      = New-IdleRequest -LifecycleEvent 'Leaver'
                $plan     = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers @{ StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.BlockedNoOnFailure', 'IdLE.Step.OnFailureCleanup') }
                $providers = @{
                    StepRegistry = @{
                        'IdLE.Step.BlockedNoOnFailure' = 'Invoke-IdlePreconditionTestNoopStep'
                        'IdLE.Step.OnFailureCleanup'   = 'Invoke-IdlePreconditionTestOnFailureStep'
                    }
                    StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.BlockedNoOnFailure', 'IdLE.Step.OnFailureCleanup')
                }

                $result = Invoke-IdlePlan -Plan $plan -Providers $providers

                $result.Status | Should -Be 'Blocked'
                $result.OnFailure.Status | Should -Be 'NotRun'
                @($result.OnFailure.Steps).Count | Should -Be 0
                @($result.Events | Where-Object Type -eq 'OnFailureRan').Count | Should -Be 0
            }

            It 'does run OnFailureSteps when OnPreconditionFalse=Fail' {
                $wfPath   = Join-Path -Path $script:FixturesPath -ChildPath 'fail-runs-onfailure.psd1'
                $req      = New-IdleRequest -LifecycleEvent 'Leaver'
                $plan     = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers @{ StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.FailRunsOnFailure', 'IdLE.Step.OnFailureCleanup') }
                $providers = @{
                    StepRegistry = @{
                        'IdLE.Step.FailRunsOnFailure' = 'Invoke-IdlePreconditionTestNoopStep'
                        'IdLE.Step.OnFailureCleanup'  = 'Invoke-IdlePreconditionTestOnFailureStep'
                    }
                    StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.FailRunsOnFailure', 'IdLE.Step.OnFailureCleanup')
                }

                $result = Invoke-IdlePlan -Plan $plan -Providers $providers

                $result.Status | Should -Be 'Failed'
                $result.OnFailure.Status | Should -Be 'Completed'
                @($result.Events | Where-Object Type -eq 'OnFailureRan').Count | Should -Be 1
            }
        }

        Context 'PreconditionEvent emission' {
            It 'emits configured PreconditionEvent when precondition fails' {
                $wfPath   = Join-Path -Path $script:FixturesPath -ChildPath 'event.psd1'
                $req      = New-IdleRequest -LifecycleEvent 'Leaver'
                $plan     = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers @{ StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.PreconditionEvent') }
                $providers = @{
                    StepRegistry = @{ 'IdLE.Step.PreconditionEvent' = 'Invoke-IdlePreconditionTestNoopStep' }
                    StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.PreconditionEvent')
                }

                $result = Invoke-IdlePlan -Plan $plan -Providers $providers

                $result.Status | Should -Be 'Blocked'

                # StepPreconditionFailed must be emitted
                $pcFailedEvent = $result.Events | Where-Object Type -eq 'StepPreconditionFailed'
                $pcFailedEvent | Should -Not -BeNullOrEmpty

                # Configured PreconditionEvent should also be emitted with the declared Type/Message
                $customEvent = $result.Events | Where-Object Type -eq 'ManualActionRequired'
                $customEvent | Should -Not -BeNullOrEmpty
                $customEvent.Message | Should -Be 'Perform Intune wipe before proceeding'
                $customEvent.Data['Reason'] | Should -Be 'BYOD wipe not confirmed'
            }
        }

        Context 'Invalid precondition schema at planning time' {
            It 'throws when a precondition node has an invalid schema' {
                $wfPath   = Join-Path -Path $script:FixturesPath -ChildPath 'invalid-schema.psd1'
                $req      = New-IdleRequest -LifecycleEvent 'Joiner'
                $providers = @{ StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.InvalidPreconditionSchema') }

                { New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers } | Should -Throw
            }

            It 'throws when OnPreconditionFalse has an invalid value' {
                $wfPath   = Join-Path -Path $script:FixturesPath -ChildPath 'invalid-onpreconditionfalse.psd1'
                $req      = New-IdleRequest -LifecycleEvent 'Joiner'
                $providers = @{ StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.InvalidOPF') }

                { New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers } | Should -Throw
            }

            It 'throws when PreconditionEvent is missing required Type' {
                $wfPath   = Join-Path -Path $script:FixturesPath -ChildPath 'invalid-event-type.psd1'
                $req      = New-IdleRequest -LifecycleEvent 'Joiner'
                $providers = @{ StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.InvalidPCEvt') }

                { New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers } | Should -Throw
            }
        }
}


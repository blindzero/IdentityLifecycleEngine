Set-StrictMode -Version Latest

BeforeAll {
    . (Join-Path (Split-Path -Path $PSScriptRoot -Parent) '_testHelpers.ps1')
    Import-IdleTestModule

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

        $Context.EventSink.WriteEvent('StepActionExecuted', "Step '$($Step.Name)' action ran.", $Step.Name, @{ StepType = $Step.Type })

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
}

Describe 'Invoke-IdlePlan - Runtime Preconditions' {

    Context 'Backward compatibility' {
        It 'step without preconditions behaves exactly as before' {
            $wfPath = New-IdleTestWorkflowFile -FileName 'no-preconditions.psd1' -Content @'
@{
  Name           = 'NoPreconditions'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{ Name = 'StepA'; Type = 'IdLE.Step.StepA' }
  )
}
'@

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner'

            $providers = @{
                StepRegistry = @{
                    'IdLE.Step.StepA' = 'Invoke-IdlePreconditionTestNoopStep'
                }
                StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.StepA')
            }

            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers
            $result = Invoke-IdlePlan -Plan $plan -Providers $providers

            $result.Status | Should -Be 'Completed'
            @($result.Steps).Count | Should -Be 1
            $result.Steps[0].Status | Should -Be 'Completed'
            ($result.Events | Where-Object Type -eq 'StepActionExecuted').Count | Should -Be 1
        }
    }

    Context 'Passing preconditions' {
        It 'step with passing precondition executes step action' {
            $wfPath = New-IdleTestWorkflowFile -FileName 'passing-precondition.psd1' -Content @'
@{
  Name           = 'PassingPrecondition'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name         = 'StepA'
      Type         = 'IdLE.Step.StepA'
      Preconditions = @(
        @{
          Equals = @{
            Path  = 'Plan.LifecycleEvent'
            Value = 'Joiner'
          }
        }
      )
    }
  )
}
'@

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner'

            $providers = @{
                StepRegistry = @{
                    'IdLE.Step.StepA' = 'Invoke-IdlePreconditionTestNoopStep'
                }
                StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.StepA')
            }

            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers
            $result = Invoke-IdlePlan -Plan $plan -Providers $providers

            $result.Status | Should -Be 'Completed'
            $result.Steps[0].Status | Should -Be 'Completed'
            ($result.Events | Where-Object Type -eq 'StepActionExecuted').Count | Should -Be 1
        }
    }

    Context 'Failing preconditions - Blocked (default)' {
        It 'failing precondition produces Blocked step and stops execution (no next step runs)' {
            $wfPath = New-IdleTestWorkflowFile -FileName 'blocked-precondition.psd1' -Content @'
@{
  Name           = 'BlockedPrecondition'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name          = 'StepA'
      Type          = 'IdLE.Step.StepA'
      Preconditions = @(
        @{
          Equals = @{
            Path  = 'Plan.LifecycleEvent'
            Value = 'Leaver'
          }
        }
      )
    }
    @{ Name = 'StepB'; Type = 'IdLE.Step.StepB' }
  )
}
'@

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner'

            $providers = @{
                StepRegistry = @{
                    'IdLE.Step.StepA' = 'Invoke-IdlePreconditionTestNoopStep'
                    'IdLE.Step.StepB' = 'Invoke-IdlePreconditionTestNoopStep'
                }
                StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.StepA', 'IdLE.Step.StepB')
            }

            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers
            $result = Invoke-IdlePlan -Plan $plan -Providers $providers

            $result.Status | Should -Be 'Blocked'
            @($result.Steps).Count | Should -Be 1
            $result.Steps[0].Name | Should -Be 'StepA'
            $result.Steps[0].Status | Should -Be 'Blocked'

            # StepB must not have been executed
            @($result.Events | Where-Object Type -eq 'StepActionExecuted').Count | Should -Be 0
            ($result.Events | Where-Object Type -eq 'StepBlocked').Count | Should -Be 1
        }

        It 'failing precondition with explicit OnPreconditionFalse=Blocked produces Blocked' {
            $wfPath = New-IdleTestWorkflowFile -FileName 'explicit-blocked.psd1' -Content @'
@{
  Name           = 'ExplicitBlocked'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name                = 'StepA'
      Type                = 'IdLE.Step.StepA'
      Preconditions       = @(
        @{
          Equals = @{
            Path  = 'Plan.LifecycleEvent'
            Value = 'Leaver'
          }
        }
      )
      OnPreconditionFalse = 'Blocked'
    }
  )
}
'@

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner'

            $providers = @{
                StepRegistry = @{
                    'IdLE.Step.StepA' = 'Invoke-IdlePreconditionTestNoopStep'
                }
                StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.StepA')
            }

            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers
            $result = Invoke-IdlePlan -Plan $plan -Providers $providers

            $result.Status | Should -Be 'Blocked'
            $result.Steps[0].Status | Should -Be 'Blocked'
        }
    }

    Context 'Failing preconditions - Fail' {
        It 'failing precondition with OnPreconditionFalse=Fail produces Failed and stops execution' {
            $wfPath = New-IdleTestWorkflowFile -FileName 'fail-precondition.psd1' -Content @'
@{
  Name           = 'FailPrecondition'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name                = 'StepA'
      Type                = 'IdLE.Step.StepA'
      Preconditions       = @(
        @{
          Equals = @{
            Path  = 'Plan.LifecycleEvent'
            Value = 'Leaver'
          }
        }
      )
      OnPreconditionFalse = 'Fail'
    }
    @{ Name = 'StepB'; Type = 'IdLE.Step.StepB' }
  )
}
'@

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner'

            $providers = @{
                StepRegistry = @{
                    'IdLE.Step.StepA' = 'Invoke-IdlePreconditionTestNoopStep'
                    'IdLE.Step.StepB' = 'Invoke-IdlePreconditionTestNoopStep'
                }
                StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.StepA', 'IdLE.Step.StepB')
            }

            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers
            $result = Invoke-IdlePlan -Plan $plan -Providers $providers

            $result.Status | Should -Be 'Failed'
            @($result.Steps).Count | Should -Be 1
            $result.Steps[0].Name | Should -Be 'StepA'
            $result.Steps[0].Status | Should -Be 'Failed'

            # StepB must not have been executed
            @($result.Events | Where-Object Type -eq 'StepActionExecuted').Count | Should -Be 0
            ($result.Events | Where-Object Type -eq 'StepFailed').Count | Should -Be 1
        }
    }

    Context 'PreconditionEvent emission' {
        It 'emits configured PreconditionEvent when precondition fails' {
            $wfPath = New-IdleTestWorkflowFile -FileName 'precondition-event.psd1' -Content @'
@{
  Name           = 'PreconditionEvent'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name              = 'StepA'
      Type              = 'IdLE.Step.StepA'
      Preconditions     = @(
        @{
          Equals = @{
            Path  = 'Plan.LifecycleEvent'
            Value = 'Leaver'
          }
        }
      )
      PreconditionEvent = @{
        Type    = 'ManualActionRequired'
        Message = 'Perform Intune wipe before disabling identity.'
        Data    = @{
          Policy   = 'BYOD'
          Platform = 'iOS'
        }
      }
    }
  )
}
'@

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner'

            $providers = @{
                StepRegistry = @{
                    'IdLE.Step.StepA' = 'Invoke-IdlePreconditionTestNoopStep'
                }
                StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.StepA')
            }

            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers
            $result = Invoke-IdlePlan -Plan $plan -Providers $providers

            $result.Status | Should -Be 'Blocked'
            $result.Steps[0].Status | Should -Be 'Blocked'

            $manualActionEvent = $result.Events | Where-Object Type -eq 'ManualActionRequired'
            $manualActionEvent | Should -Not -BeNullOrEmpty
            $manualActionEvent.Message | Should -Be 'Perform Intune wipe before disabling identity.'
            $manualActionEvent.Data.Policy | Should -Be 'BYOD'
            $manualActionEvent.Data.Platform | Should -Be 'iOS'
            $manualActionEvent.StepName | Should -Be 'StepA'
        }

        It 'emits StepBlocked event even without PreconditionEvent configured' {
            $wfPath = New-IdleTestWorkflowFile -FileName 'no-event.psd1' -Content @'
@{
  Name           = 'NoEvent'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name          = 'StepA'
      Type          = 'IdLE.Step.StepA'
      Preconditions = @(
        @{
          Equals = @{
            Path  = 'Plan.LifecycleEvent'
            Value = 'Leaver'
          }
        }
      )
    }
  )
}
'@

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner'

            $providers = @{
                StepRegistry = @{
                    'IdLE.Step.StepA' = 'Invoke-IdlePreconditionTestNoopStep'
                }
                StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.StepA')
            }

            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers
            $result = Invoke-IdlePlan -Plan $plan -Providers $providers

            $result.Status | Should -Be 'Blocked'
            ($result.Events | Where-Object Type -eq 'StepBlocked').Count | Should -Be 1
        }
    }

    Context 'Schema validation' {
        It 'rejects invalid OnPreconditionFalse value at planning time' {
            $wfPath = New-IdleTestWorkflowFile -FileName 'bad-opf.psd1' -Content @'
@{
  Name           = 'BadOnPreconditionFalse'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name                = 'StepA'
      Type                = 'IdLE.Step.StepA'
      Preconditions       = @(
        @{ Equals = @{ Path = 'Plan.LifecycleEvent'; Value = 'Joiner' } }
      )
      OnPreconditionFalse = 'InvalidValue'
    }
  )
}
'@

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner'

            { New-IdlePlan -WorkflowPath $wfPath -Request $req } | Should -Throw
        }

        It 'rejects invalid Preconditions condition schema at planning time' {
            $wfPath = New-IdleTestWorkflowFile -FileName 'bad-precond.psd1' -Content @'
@{
  Name           = 'BadPrecondition'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name          = 'StepA'
      Type          = 'IdLE.Step.StepA'
      Preconditions = @(
        @{ UnknownKey = 'invalid' }
      )
    }
  )
}
'@

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner'

            { New-IdlePlan -WorkflowPath $wfPath -Request $req } | Should -Throw
        }
    }
}

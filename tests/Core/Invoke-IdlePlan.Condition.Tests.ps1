Set-StrictMode -Version Latest

BeforeDiscovery {
    . (Join-Path (Split-Path -Path $PSScriptRoot -Parent) '_testHelpers.ps1')
    Import-IdleTestModule

    function global:Invoke-IdleConditionTestEmitStep {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [ValidateNotNull()]
            [object] $Context,

            [Parameter(Mandatory)]
            [ValidateNotNull()]
            [object] $Step
        )

        $Context.EventSink.WriteEvent('Custom', 'Hello', $Step.Name, @{ StepType = $Step.Type })

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
    Remove-Item -Path 'Function:\Invoke-IdleConditionTestEmitStep' -ErrorAction SilentlyContinue
}

InModuleScope 'IdLE.Core' {
    Describe 'Invoke-IdlePlan - Condition applicability' {
        Context 'Condition evaluation' {
            It 'does not execute a step when plan marks it as NotApplicable' {
                $wfPath = Join-Path -Path $TestDrive -ChildPath 'condition.psd1'
                Set-Content -Path $wfPath -Encoding UTF8 -Value @'
@{
  Name           = 'Condition Demo'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name      = 'Emit'
      Type      = 'IdLE.Step.EmitEvent'
      Condition = @{
        Equals = @{
          Path  = 'Plan.LifecycleEvent'
          Value = 'Leaver'
        }
      }
    }
  )
}
'@

                $req = New-IdleRequest -LifecycleEvent 'Joiner'
                $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req

                $providers = @{ StepRegistry = @{ 'IdLE.Step.EmitEvent' = 'Invoke-IdleConditionTestEmitStep' } }

                $result = Invoke-IdlePlan -Plan $plan -Providers $providers

                $result.Status | Should -Be 'Completed'
                $result.Steps[0].Status | Should -Be 'NotApplicable'
                @($result.Events | Where-Object Type -eq 'Custom').Count | Should -Be 0
                @($result.Events | Where-Object Type -eq 'StepNotApplicable').Count | Should -Be 1
            }

            It 'runs a step when condition is met' {
                $wfPath = Join-Path -Path $TestDrive -ChildPath 'condition2.psd1'
                Set-Content -Path $wfPath -Encoding UTF8 -Value @'
@{
  Name           = 'Condition Demo'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name      = 'Emit'
      Type      = 'IdLE.Step.EmitEvent'
      Condition = @{
        Equals = @{
          Path  = 'Plan.LifecycleEvent'
          Value = 'Joiner'
        }
      }
    }
  )
}
'@

                $req = New-IdleRequest -LifecycleEvent 'Joiner'
                $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req

                $providers = @{ StepRegistry = @{ 'IdLE.Step.EmitEvent' = 'Invoke-IdleConditionTestEmitStep' } }

                $result = Invoke-IdlePlan -Plan $plan -Providers $providers

                $result.Status | Should -Be 'Completed'
                $result.Steps[0].Status | Should -Be 'Completed'
                ($result.Events | Where-Object Type -eq 'Custom').Count | Should -Be 1
            }
        }
    }
}

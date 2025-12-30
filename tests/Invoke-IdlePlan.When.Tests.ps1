BeforeAll {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\src\IdLE\IdLE.psd1'
    Import-Module $modulePath -Force
}

Describe 'Invoke-IdlePlan - When conditions' {

    It 'skips a step when condition is not met' {
        $wfPath = Join-Path -Path $TestDrive -ChildPath 'when.psd1'
        Set-Content -Path $wfPath -Encoding UTF8 -Value @'
@{
  Name           = 'When Demo'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'Emit'
      Type = 'IdLE.Step.EmitEvent'
      When = @{ Path = 'Plan.LifecycleEvent'; Equals = 'Leaver' }
    }
  )
}
'@

        $req  = New-IdleLifecycleRequest -LifecycleEvent 'Joiner'
        $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req

        $emit = {
            param($Context, $Step)
            $Context.EventSink.WriteEvent('Custom', 'Hello', $Step.Name, @{ StepType = $Step.Type })
            [pscustomobject]@{
                PSTypeName = 'IdLE.StepResult'
                Name       = [string]$Step.Name
                Type       = [string]$Step.Type
                Status     = 'Completed'
                Error      = $null
            }
        }

        $providers = @{
            StepRegistry = @{
                'IdLE.Step.EmitEvent' = $emit
            }
        }

        $result = Invoke-IdlePlan -Plan $plan -Providers $providers

        $result.Status | Should -Be 'Completed'
        $result.Steps[0].Status | Should -Be 'Skipped'
        ($result.Events | Where-Object Type -eq 'Custom').Count | Should -Be 0
        ($result.Events | Where-Object Type -eq 'StepSkipped').Count | Should -Be 1
    }

    It 'runs a step when condition is met' {
        $wfPath = Join-Path -Path $TestDrive -ChildPath 'when2.psd1'
        Set-Content -Path $wfPath -Encoding UTF8 -Value @'
@{
  Name           = 'When Demo'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'Emit'
      Type = 'IdLE.Step.EmitEvent'
      When = @{ Path = 'Plan.LifecycleEvent'; Equals = 'Joiner' }
    }
  )
}
'@

        $req  = New-IdleLifecycleRequest -LifecycleEvent 'Joiner'
        $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req

        $emit = {
            param($Context, $Step)
            $Context.EventSink.WriteEvent('Custom', 'Hello', $Step.Name, @{ StepType = $Step.Type })
            [pscustomobject]@{
                PSTypeName = 'IdLE.StepResult'
                Name       = [string]$Step.Name
                Type       = [string]$Step.Type
                Status     = 'Completed'
                Error      = $null
            }
        }

        $providers = @{
            StepRegistry = @{
                'IdLE.Step.EmitEvent' = $emit
            }
        }

        $result = Invoke-IdlePlan -Plan $plan -Providers $providers

        $result.Status | Should -Be 'Completed'
        $result.Steps[0].Status | Should -Be 'Completed'
        ($result.Events | Where-Object Type -eq 'Custom').Count | Should -Be 1
    }
}

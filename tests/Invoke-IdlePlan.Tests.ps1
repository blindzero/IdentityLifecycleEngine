BeforeAll {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\src\IdLE\IdLE.psd1'
    Import-Module $modulePath -Force
}

Describe 'Invoke-IdlePlan' {
    It 'returns an execution result with events in deterministic order' {
      $wfPath = Join-Path -Path $TestDrive -ChildPath 'joiner.psd1'
      Set-Content -Path $wfPath -Encoding UTF8 -Value @'
@{
  Name           = 'Joiner - Standard'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{ Name = 'ResolveIdentity'; Type = 'IdLE.Step.ResolveIdentity' }
    @{ Name = 'EnsureAttributes'; Type = 'IdLE.Step.EnsureAttributes' }
  )
}
'@

      $req  = New-IdleLifecycleRequest -LifecycleEvent 'Joiner'
      $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req

      $noop = {
          param($Context, $Step)
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
              'IdLE.Step.ResolveIdentity'  = $noop
              'IdLE.Step.EnsureAttributes' = $noop
          }
      }

      $result = Invoke-IdlePlan -Plan $plan -Providers $providers

      $result.PSTypeNames | Should -Contain 'IdLE.ExecutionResult'
      $result.Status | Should -Be 'Completed'
      @($result.Steps).Count | Should -Be 2

      @($result.Events).Count | Should -BeGreaterThan 0
      $result.Events[0].Type | Should -Be 'RunStarted'
      $result.Events[-1].Type | Should -Be 'RunCompleted'

      $result.Steps[0].Status | Should -Be 'Completed'
      $result.Steps[1].Status | Should -Be 'Completed'
    }

    It 'supports -WhatIf and does not execute' {
        $plan = [pscustomobject]@{
            CorrelationId = 'test'
            Steps         = @(
                @{ Name = 'A'; Type = 'X' }
            )
        }

        $result = Invoke-IdlePlan -Plan $plan -WhatIf
        $result.Status | Should -Be 'WhatIf'
        @($result.Events).Count | Should -Be 0
    }

    It 'can stream events to an object sink with WriteEvent(event)' {
      $wfPath = Join-Path -Path $TestDrive -ChildPath 'joiner.psd1'
      Set-Content -Path $wfPath -Encoding UTF8 -Value @'
@{
  Name           = 'Joiner - Standard'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{ Name = 'ResolveIdentity'; Type = 'IdLE.Step.ResolveIdentity' }
  )
}
'@

      $req  = New-IdleLifecycleRequest -LifecycleEvent 'Joiner'
      $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req

      $noop = {
          param($Context, $Step)
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
              'IdLE.Step.ResolveIdentity' = $noop
          }
      }

      $sinkEvents = [System.Collections.Generic.List[object]]::new()
      $sinkObject = [pscustomobject]@{}
      $writeMethod = {
          param($e)
          [void]$sinkEvents.Add($e)
      }.GetNewClosure()
      $null = Add-Member -InputObject $sinkObject -MemberType ScriptMethod -Name 'WriteEvent' -Value $writeMethod -Force

      $result = Invoke-IdlePlan -Plan $plan -Providers $providers -EventSink $sinkObject

      $sinkEvents.Count | Should -BeGreaterThan 0
      $sinkEvents[0].PSTypeNames | Should -Contain 'IdLE.Event'
      $result.Events[0].Type | Should -Be 'RunStarted'
    }

    It 'rejects a ScriptBlock -EventSink (security)' {
      $wfPath = Join-Path -Path $TestDrive -ChildPath 'joiner.psd1'
      Set-Content -Path $wfPath -Encoding UTF8 -Value @'
@{
  Name           = 'Joiner - Standard'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{ Name = 'ResolveIdentity'; Type = 'IdLE.Step.ResolveIdentity' }
  )
}
'@

      $req  = New-IdleLifecycleRequest -LifecycleEvent 'Joiner'
      $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req

      $noop = {
          param($Context, $Step)
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
              'IdLE.Step.ResolveIdentity' = $noop
          }
      }

      $sink = { param($e) } 
      { Invoke-IdlePlan -Plan $plan -Providers $providers -EventSink $sink } | Should -Throw
    }

    It 'executes a registered step and returns Completed status' {
      $wfPath = Join-Path -Path $TestDrive -ChildPath 'emit.psd1'
      Set-Content -Path $wfPath -Encoding UTF8 -Value @'
@{
  Name           = 'Demo'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{ Name = 'Emit'; Type = 'IdLE.Step.EmitEvent'; With = @{ Message = 'Hello' } }
  )
}
'@

      $req  = New-IdleLifecycleRequest -LifecycleEvent 'Joiner'
      $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req

      $emit = {
          param($Context, $Step)
          $Context.EventSink.WriteEvent('Custom', 'Hello from test step', $Step.Name, @{ StepType = $Step.Type })

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

    It 'fails planning when a step is missing Type' {
      $wfPath = Join-Path -Path $TestDrive -ChildPath 'bad.psd1'
      Set-Content -Path $wfPath -Encoding UTF8 -Value @'
@{
  Name           = 'Bad'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{ Name = 'NoType' }
  )
}
'@

      $req = New-IdleLifecycleRequest -LifecycleEvent 'Joiner'

      { New-IdlePlan -WorkflowPath $wfPath -Request $req } | Should -Throw
    }

    It 'fails planning when When schema is invalid' {
      $wfPath = Join-Path -Path $TestDrive -ChildPath 'bad-when.psd1'
      Set-Content -Path $wfPath -Encoding UTF8 -Value @'
@{
  Name           = 'BadWhen'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'Emit'
      Type = 'IdLE.Step.EmitEvent'
      When = @{ Path = 'Plan.LifecycleEvent'; Equals = 'Joiner'; Exists = $true }
    }
  )
}
'@

      $req = New-IdleLifecycleRequest -LifecycleEvent 'Joiner'
      { New-IdlePlan -WorkflowPath $wfPath -Request $req } | Should -Throw
    }
}

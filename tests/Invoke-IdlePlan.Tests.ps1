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

        $result = Invoke-IdlePlan -Plan $plan

        $result.PSTypeNames | Should -Contain 'IdLE.ExecutionResult'
        $result.Status | Should -Be 'Completed'
        @($result.Steps).Count | Should -Be 2

        # Basic event checks
        @($result.Events).Count | Should -BeGreaterThan 0
        $result.Events[0].Type | Should -Be 'RunStarted'
        $result.Events[-1].Type | Should -Be 'RunCompleted'

        # Step status placeholder
        $result.Steps[0].Status | Should -Be 'NotImplemented'
        $result.Steps[1].Status | Should -Be 'NotImplemented'
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

    It 'can stream events to a ScriptBlock sink' {
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

        $sinkEvents = [System.Collections.Generic.List[object]]::new()
        $sink = {
            param($e)
            [void]$sinkEvents.Add($e)
        }.GetNewClosure()
        
        $result = Invoke-IdlePlan -Plan $plan -EventSink $sink

        @($sinkEvents).Count | Should -BeGreaterThan 0
        $sinkEvents[0].PSTypeNames | Should -Contain 'IdLE.Event'
        $result.Events[0].Type | Should -Be 'RunStarted'
    }
}

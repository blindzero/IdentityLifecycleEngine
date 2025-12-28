BeforeAll {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\src\IdLE\IdLE.psd1'
    Import-Module $modulePath -Force
}

Describe 'New-IdlePlan' {

    It 'creates a plan with normalized steps' {
        $wfPath = Join-Path -Path $TestDrive -ChildPath 'joiner.psd1'
        Set-Content -Path $wfPath -Encoding UTF8 -Value @'
@{
  Name           = 'Joiner - Standard'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{ Name = 'ResolveIdentity'; Type = 'IdLE.Step.ResolveIdentity' }
    @{ Name = 'EnsureAttributes'; Type = 'IdLE.Step.EnsureAttributes'; With = @{ Mode = 'Minimal' } }
  )
}
'@

        $req  = New-IdleLifecycleRequest -LifecycleEvent 'Joiner'
        $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers @{ Dummy = $true }

        $plan | Should -Not -BeNullOrEmpty
        $plan.PSTypeNames | Should -Contain 'IdLE.Plan'
        $plan.WorkflowName | Should -Be 'Joiner - Standard'
        $plan.LifecycleEvent | Should -Be 'Joiner'
        $plan.CorrelationId | Should -Be $req.CorrelationId

        @($plan.Steps).Count | Should -Be 2
        $plan.Steps[0].PSTypeNames | Should -Contain 'IdLE.PlanStep'
        $plan.Steps[0].Name | Should -Be 'ResolveIdentity'
        $plan.Steps[0].Type | Should -Be 'IdLE.Step.ResolveIdentity'

        @($plan.Actions).Count | Should -Be 0
        @($plan.Warnings).Count | Should -Be 0

        $plan.Providers.Dummy | Should -BeTrue
    }

    It 'throws when request LifecycleEvent does not match workflow LifecycleEvent' {
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

        $req = New-IdleLifecycleRequest -LifecycleEvent 'Leaver'

        try {
            New-IdlePlan -WorkflowPath $wfPath -Request $req | Out-Null
            throw 'Expected an exception but none was thrown.'
        }
        catch {
            $_.Exception.Message | Should -Match 'does not match request LifecycleEvent'
        }
    }
}

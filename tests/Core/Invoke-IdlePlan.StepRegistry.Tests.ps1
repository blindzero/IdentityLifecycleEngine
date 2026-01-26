BeforeAll {
    . (Join-Path (Split-Path -Path $PSScriptRoot -Parent) '_testHelpers.ps1')
    Import-IdleTestModule

    # The meta module (IdLE) does not automatically import optional step packs.
    # For this test we explicitly load the built-in steps module so that
    # Get-IdleStepRegistry can discover the handler via Get-Command.
    $repoRoot = Get-RepoRootPath
    $stepsManifestPath = Join-Path -Path $repoRoot -ChildPath 'src/IdLE.Steps.Common/IdLE.Steps.Common.psd1'
    Import-Module -Name $stepsManifestPath -Force -ErrorAction Stop
}

AfterAll {
    # Cleanup to avoid influencing other tests that might rely on a clean module state.
    Remove-Module -Name 'IdLE.Steps.Common' -ErrorAction SilentlyContinue
}

Describe 'Invoke-IdlePlan - StepRegistry' {
    It 'executes built-in steps without a host-provided StepRegistry' {
        $wfPath = Join-Path -Path $TestDrive -ChildPath 'emit-built-in.psd1'
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

        # Intentionally no Providers.StepRegistry here.
        $providers = @{}

        $result = Invoke-IdlePlan -Plan $plan -Providers $providers

        $result.Status | Should -Be 'Completed'
        @($result.Steps).Count | Should -Be 1
        $result.Steps[0].Status | Should -Be 'Completed'

        # The built-in EmitEvent step emits a Custom event.
        ($result.Events | Where-Object Type -eq 'Custom').Count | Should -Be 1
    }
}

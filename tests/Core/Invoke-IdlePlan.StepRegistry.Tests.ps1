Set-StrictMode -Version Latest

BeforeAll {
    . (Join-Path (Split-Path -Path $PSScriptRoot -Parent) '_testHelpers.ps1')
    Import-IdleTestModule

    $script:RepoRoot = Get-RepoRootPath
    $script:StepsManifestPath = Join-Path -Path $script:RepoRoot -ChildPath 'src/IdLE.Steps.Common/IdLE.Steps.Common.psd1'

    Import-Module -Name $script:StepsManifestPath -Force -ErrorAction Stop
}

AfterAll {
    Remove-Module -Name 'IdLE.Steps.Common' -ErrorAction SilentlyContinue
}

Describe 'Invoke-IdlePlan - StepRegistry' {
    Context 'Built-in handlers' {
        It 'executes built-in steps without a host-provided StepRegistry' {
            $wfPath = New-IdleTestWorkflowFile -FileName 'emit-built-in.psd1' -Content @'
@{
  Name           = 'Demo'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{ Name = 'Emit'; Type = 'IdLE.Step.EmitEvent'; With = @{ Message = 'Hello' } }
  )
}
'@

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner'
            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req

            $result = Invoke-IdlePlan -Plan $plan -Providers @{}

            $result.Status | Should -Be 'Completed'
            @($result.Steps).Count | Should -Be 1
            $result.Steps[0].Status | Should -Be 'Completed'
            ($result.Events | Where-Object Type -eq 'Custom').Count | Should -Be 1
        }
    }
}

Set-StrictMode -Version Latest

BeforeAll {
    . (Join-Path (Split-Path -Path $PSScriptRoot -Parent) '_testHelpers.ps1')
    Import-IdleTestModule
}

Describe 'Test-IdleWorkflow' {
    Context 'Validation' {
        It 'returns a valid result for a minimal correct workflow' {
            $wfPath = New-IdleTestWorkflowFile -FileName 'joiner.psd1' -Content @'
@{
  Name           = 'Joiner - Standard'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{ Name = 'ResolveIdentity'; Type = 'IdLE.Step.ResolveIdentity' }
  )
}
'@

            $result = Test-IdleWorkflow -WorkflowPath $wfPath

            $result | Should -Not -BeNullOrEmpty
            $result.IsValid | Should -BeTrue
            $result.WorkflowName | Should -Be 'Joiner - Standard'
            $result.LifecycleEvent | Should -Be 'Joiner'
            $result.StepCount | Should -Be 1
        }

        It 'accepts OnFailureSteps as an optional top-level section' {
            $wfPath = New-IdleTestWorkflowFile -FileName 'joiner-onfailure.psd1' -Content @'
@{
  Name           = 'Joiner - OnFailure'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{ Name = 'ResolveIdentity'; Type = 'IdLE.Step.ResolveIdentity' }
  )
  OnFailureSteps = @(
    @{ Name = 'Containment'; Type = 'IdLE.Step.DisableIdentity' }
  )
}
'@

            { Test-IdleWorkflow -WorkflowPath $wfPath } | Should -Not -Throw

            $result = Test-IdleWorkflow -WorkflowPath $wfPath
            $result.IsValid | Should -BeTrue
            $result.WorkflowName | Should -Be 'Joiner - OnFailure'
            $result.LifecycleEvent | Should -Be 'Joiner'
            $result.StepCount | Should -Be 1
        }
    }

    Context 'Schema errors' {
        It 'rejects unknown root keys such as CleanupSteps' {
            $wfPath = New-IdleTestWorkflowFile -FileName 'joiner-cleanupsteps.psd1' -Content @'
@{
  Name           = 'Joiner - Invalid'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{ Name = 'ResolveIdentity'; Type = 'IdLE.Step.ResolveIdentity' }
  )
  CleanupSteps   = @(
    @{ Name = 'Nope'; Type = 'IdLE.Step.DisableIdentity' }
  )
}
'@

            try {
                Test-IdleWorkflow -WorkflowPath $wfPath | Out-Null
                throw 'Expected an exception but none was thrown.'
            }
            catch {
                $_.Exception.Message | Should -Match 'Unknown root key'
                $_.Exception.Message | Should -Match 'CleanupSteps'
            }
        }

        It 'fails when workflow LifecycleEvent does not match request LifecycleEvent' {
            $wfPath = New-IdleTestWorkflowFile -FileName 'joiner-mismatch.psd1' -Content @'
@{
  Name           = 'Joiner - Standard'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{ Name = 'ResolveIdentity'; Type = 'IdLE.Step.ResolveIdentity' }
  )
}
'@

            $req = New-IdleTestRequest -LifecycleEvent 'Leaver'

            try {
                Test-IdleWorkflow -WorkflowPath $wfPath -Request $req | Out-Null
                throw 'Expected an exception but none was thrown.'
            }
            catch {
                $_.Exception.Message | Should -Match 'does not match request LifecycleEvent'
            }
        }
    }
}

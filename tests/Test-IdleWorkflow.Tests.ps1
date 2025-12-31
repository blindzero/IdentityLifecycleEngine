BeforeAll {
    . (Join-Path $PSScriptRoot '_testHelpers.ps1')
    Import-IdleTestModule
}

Describe 'Test-IdleWorkflow' {

    It 'returns a valid result for a minimal correct workflow' {
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

        $req = New-IdleLifecycleRequest -LifecycleEvent 'Joiner'
        $result = Test-IdleWorkflow -WorkflowPath $wfPath -Request $req

        $result.IsValid | Should -BeTrue
        $result.WorkflowName | Should -Be 'Joiner - Standard'
        $result.LifecycleEvent | Should -Be 'Joiner'
        $result.StepCount | Should -Be 1
    }

    It 'throws for unknown root keys (strict validation)' {
        $wfPath = Join-Path -Path $TestDrive -ChildPath 'bad-root.psd1'
        Set-Content -Path $wfPath -Encoding UTF8 -Value @'
@{
  Name           = 'Joiner - Standard'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{ Name = 'ResolveIdentity'; Type = 'IdLE.Step.ResolveIdentity' }
  )
  Bogus          = 'nope'
}
'@

        try {
            Test-IdleWorkflow -WorkflowPath $wfPath | Out-Null
            throw 'Expected an exception but none was thrown.'
        }
        catch {
            $_.Exception.Message | Should -Match 'Unknown root key'
        }
    }

    It 'throws when a step is missing required keys' {
        $wfPath = Join-Path -Path $TestDrive -ChildPath 'bad-step.psd1'
        Set-Content -Path $wfPath -Encoding UTF8 -Value @'
@{
  Name           = 'Joiner - Standard'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{ Name = 'ResolveIdentity' }
  )
}
'@

        try {
            Test-IdleWorkflow -WorkflowPath $wfPath | Out-Null
            throw 'Expected an exception but none was thrown.'
        }
        catch {
            $_.Exception.Message | Should -Match 'Steps\[0\]\.Type'
        }
    }

    It 'throws when the workflow contains ScriptBlocks (data-only rule)' {
        $wfPath = Join-Path -Path $TestDrive -ChildPath 'bad-sb.psd1'
        Set-Content -Path $wfPath -Encoding UTF8 -Value @'
@{
  Name           = 'Joiner - Standard'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{ Name = 'ResolveIdentity'; Type = 'IdLE.Step.ResolveIdentity'; With = @{ X = { "NOPE" } } }
  )
}
'@

        try {
            Test-IdleWorkflow -WorkflowPath $wfPath | Out-Null
            throw 'Expected an exception but none was thrown.'
        }
        catch {
            $_.Exception.Message | Should -Match 'ScriptBlocks are not allowed'
        }
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
            Test-IdleWorkflow -WorkflowPath $wfPath -Request $req | Out-Null
            throw 'Expected an exception but none was thrown.'
        }
        catch {
            $_.Exception.Message | Should -Match 'does not match request LifecycleEvent'
        }
    }
}

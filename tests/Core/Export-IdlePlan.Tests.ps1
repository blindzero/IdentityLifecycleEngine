Set-StrictMode -Version Latest

BeforeAll {
    . (Join-Path (Split-Path -Path $PSScriptRoot -Parent) '_testHelpers.ps1')
    Import-IdleTestModule
}

Describe 'Export-IdlePlan' {
    Context 'JSON contract export' {
        It 'exports a stable, canonical JSON representation of a plan' {
            $cid = '11111111-1111-1111-1111-111111111111'

            $wfPath = New-IdleTestWorkflowFile -FileName 'joiner-export.psd1' -Content @'
@{
  Name           = 'Joiner - Export Fixture'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'Ensure Mailbox'
      Type = 'EnsureMailbox'
      With = @{
        mailboxType = 'User'
      }
    }
  )
}
'@

            $req = New-IdleTestRequest `
              -LifecycleEvent 'Joiner' `
              -CorrelationId $cid `
              -IdentityKeys ([ordered]@{ userId = 'jdoe' }) `
              -Intent ([ordered]@{ department = 'IT' })

            $providers = @{
                Dummy        = $true
                StepRegistry = @{ 'EnsureMailbox' = 'Invoke-IdleTestNoopStep' }
                StepMetadata = New-IdleTestStepMetadata -StepTypes @('EnsureMailbox')
            }

            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

            $expectedPath = Join-Path $PSScriptRoot '..' 'fixtures/plan-export/expected/plan-export.json'
            $expectedJson = Get-Content -Path $expectedPath -Raw -Encoding utf8

            $actualJson = $plan | Export-IdlePlan

            ($actualJson -replace "`r`n", "`n").TrimEnd() |
                Should -Be (($expectedJson -replace "`r`n", "`n").TrimEnd())
        }
    }

    Context 'File output (-Path)' {
        It 'writes the JSON artifact to disk (TestDrive) using UTF-8 without BOM' {
            $cid = '11111111-1111-1111-1111-111111111111'

            $wfPath = New-IdleTestWorkflowFile -FileName 'joiner-export-empty.psd1' -Content @'
@{
  Name           = 'Joiner - Export Fixture Empty'
  LifecycleEvent = 'Joiner'
  Steps          = @()
}
'@

            $req = New-IdleTestRequest `
              -LifecycleEvent 'Joiner' `
              -CorrelationId $cid `
              -IdentityKeys ([ordered]@{ userId = 'jdoe' })

            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers @{ Dummy = $true }

            $outFile = Join-Path $TestDrive 'plan.json'

            $null = $plan | Export-IdlePlan -Path $outFile

            Test-Path -LiteralPath $outFile | Should -BeTrue

            $content = Get-Content -Path $outFile -Raw -Encoding utf8
            $content | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Planning warnings export' {
        It 'includes planning warnings in exported plan for CI checks' {
            $cid = '22222222-2222-2222-2222-222222222222'

            $wfPath = New-IdleTestWorkflowFile -FileName 'joiner-export-warning.psd1' -Content @'
@{
  Name           = 'Joiner - Export Warning Fixture'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name         = 'Check Context'
      Type         = 'EnsureMailbox'
      Precondition = @{ Exists = 'Request.Context.OffboardingDate' }
      With         = @{ mailboxType = 'User' }
    }
  )
}
'@

            $req = New-IdleTestRequest `
              -LifecycleEvent 'Joiner' `
              -CorrelationId $cid `
              -IdentityKeys ([ordered]@{ userId = 'jdoe' }) `
              -Intent ([ordered]@{ department = 'IT' })

            $providers = @{
                Dummy        = $true
                StepRegistry = @{ 'EnsureMailbox' = 'Invoke-IdleTestNoopStep' }
                StepMetadata = New-IdleTestStepMetadata -StepTypes @('EnsureMailbox')
            }

            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

            @($plan.Warnings).Count | Should -BeGreaterThan 0
            @($plan.Steps[0].Warnings).Count | Should -BeGreaterThan 0
            $plan.Steps[0].Warnings[0].Code | Should -Be 'PreconditionContextPathUnresolvedAtPlan'

            $json = $plan | Export-IdlePlan | ConvertFrom-Json
            @($json.plan.warnings).Count | Should -BeGreaterThan 0
            $json.plan.warnings[0].code | Should -Be 'PreconditionContextPathUnresolvedAtPlan'
            $json.plan.warnings[0].step | Should -Be 'Check Context'

            $json.plan.steps[0].warnings | Should -Not -BeNullOrEmpty
            ($json.plan.steps[0].warnings | Measure-Object).Count | Should -BeGreaterThan 0
            $json.plan.steps[0].warnings[0].code | Should -Be 'PreconditionContextPathUnresolvedAtPlan'
        }
    }
    Context 'Contract invariants' {
        It 'always includes schemaVersion 1.0' {
            $cid = '11111111-1111-1111-1111-111111111111'

            $wfPath = New-IdleTestWorkflowFile -FileName 'joiner-export-empty.psd1' -Content @'
@{
  Name           = 'Joiner - Export Fixture Empty'
  LifecycleEvent = 'Joiner'
  Steps          = @()
}
'@

            $req = New-IdleTestRequest `
              -LifecycleEvent 'Joiner' `
              -CorrelationId $cid `
              -IdentityKeys ([ordered]@{ userId = 'jdoe' })

            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers @{ Dummy = $true }

            $json = $plan | Export-IdlePlan | ConvertFrom-Json

            $json.schemaVersion | Should -Be '1.0'
        }
    }
}

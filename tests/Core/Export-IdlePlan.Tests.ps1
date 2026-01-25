# Requires -Version 7.0
Set-StrictMode -Version Latest

BeforeAll {
    . (Join-Path (Split-Path -Path $PSScriptRoot -Parent) '_testHelpers.ps1')
    Import-IdleTestModule
}

Describe 'Export-IdlePlan' {

    Context 'JSON contract export' {

        It 'exports a stable, canonical JSON representation of a plan' {
            # Arrange
            $cid = '11111111-1111-1111-1111-111111111111'

            $wfPath = Join-Path -Path $TestDrive -ChildPath 'joiner-export.psd1'
            Set-Content -Path $wfPath -Encoding UTF8 -Value @'
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

            # IMPORTANT: Provide request intent payload so the export can include request.input.
            $req = New-IdleLifecycleRequest `
                -LifecycleEvent 'Joiner' `
                -CorrelationId  $cid `
                -IdentityKeys   ([ordered]@{ userId = 'jdoe' }) `
                -DesiredState   ([ordered]@{ department = 'IT' })

            $providers = @{
                Dummy        = $true
                StepRegistry = @{
                    'EnsureMailbox' = 'Invoke-IdleTestNoopStep'
                }
                StepMetadata = New-IdleTestStepMetadata -StepTypes @('EnsureMailbox')
            }
            
            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

            $expectedPath = Join-Path $PSScriptRoot 'fixtures/plan-export/expected/plan-export.json'
            $expectedJson = Get-Content -Path $expectedPath -Raw -Encoding utf8

            # Act
            $actualJson = $plan | Export-IdlePlan

            # Assert
            # Normalize trailing whitespace (EOF newline differences) and line endings (Windows/Linux).
            ($actualJson -replace "`r`n", "`n").TrimEnd() |
                Should -Be (($expectedJson -replace "`r`n", "`n").TrimEnd())
        }
    }

    Context 'File output (-Path)' {

        It 'writes the JSON artifact to disk (TestDrive) using UTF-8 without BOM' {
            # Arrange
            $cid = '11111111-1111-1111-1111-111111111111'

            $wfPath = Join-Path -Path $TestDrive -ChildPath 'joiner-export-empty.psd1'
            Set-Content -Path $wfPath -Encoding UTF8 -Value @'
@{
  Name           = 'Joiner - Export Fixture Empty'
  LifecycleEvent = 'Joiner'
  Steps          = @()
}
'@

            $req = New-IdleLifecycleRequest `
                -LifecycleEvent 'Joiner' `
                -CorrelationId  $cid `
                -IdentityKeys   ([ordered]@{ userId = 'jdoe' })

            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers @{ Dummy = $true }

            $outFile = Join-Path $TestDrive 'plan.json'

            # Act
            $null = $plan | Export-IdlePlan -Path $outFile

            # Assert
            Test-Path -LiteralPath $outFile | Should -BeTrue

            $content = Get-Content -Path $outFile -Raw -Encoding utf8
            $content | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Contract invariants' {

        It 'always includes schemaVersion 1.0' {
            # Arrange
            $cid = '11111111-1111-1111-1111-111111111111'

            $wfPath = Join-Path -Path $TestDrive -ChildPath 'joiner-export-empty.psd1'
            Set-Content -Path $wfPath -Encoding UTF8 -Value @'
@{
  Name           = 'Joiner - Export Fixture Empty'
  LifecycleEvent = 'Joiner'
  Steps          = @()
}
'@

            $req = New-IdleLifecycleRequest `
                -LifecycleEvent 'Joiner' `
                -CorrelationId  $cid `
                -IdentityKeys   ([ordered]@{ userId = 'jdoe' })

            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers @{ Dummy = $true }

            # Act
            $json = $plan | Export-IdlePlan | ConvertFrom-Json

            # Assert
            $json.schemaVersion | Should -Be '1.0'
        }
    }
}

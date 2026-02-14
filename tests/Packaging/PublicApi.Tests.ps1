Set-StrictMode -Version Latest

BeforeAll {
    . (Join-Path (Split-Path -Path $PSScriptRoot -Parent) '_testHelpers.ps1')
    Import-IdleTestModule
}

Describe 'IdLE public API surface' {
    Context 'Commands' {
        It 'Expected commands exist' {
            $expected = @(
                'Invoke-IdlePlan',
                'New-IdleRequest',
                'New-IdlePlan',
                'Test-IdleWorkflow'
            )

            foreach ($name in $expected) {
                Get-Command -Name $name -ErrorAction Stop | Should -Not -BeNullOrEmpty
            }
        }
    }

    Context 'Help metadata' {
        It 'Exported IdLE functions have comment-based help (Synopsis + Description + Examples)' {
            $commands = Get-Command -Module IdLE -CommandType Function
            $commands | Should -Not -BeNullOrEmpty

            foreach ($cmd in $commands) {
                $help = Get-Help -Name $cmd.Name -ErrorAction Stop

                $help.Synopsis | Should -Not -BeNullOrEmpty

                $descText =
                    if ($help.Description -and $help.Description.Text) { ($help.Description.Text -join "`n").Trim() }
                    else { '' }

                $descText | Should -Not -BeNullOrEmpty

                $exampleCount =
                    if ($help.Examples -and $help.Examples.Example) {
                        @($help.Examples.Example).Count
                    }
                    else {
                        0
                    }

                $exampleCount | Should -BeGreaterThan 0
            }
        }
    }
}


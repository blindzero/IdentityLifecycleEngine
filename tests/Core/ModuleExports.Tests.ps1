Set-StrictMode -Version Latest

BeforeAll {
    . (Join-Path (Split-Path -Path $PSScriptRoot -Parent) '_testHelpers.ps1')
    $script:RepoRoot = Get-RepoRootPath
}

Describe 'Module Export Consistency' {
    Context 'IdLE.Core module exports' {
        BeforeAll {
            $script:OriginalIdleAllowInternalImport = $env:IDLE_ALLOW_INTERNAL_IMPORT
            $env:IDLE_ALLOW_INTERNAL_IMPORT = '1'

            $script:CoreModulePath = Join-Path -Path $script:RepoRoot -ChildPath 'src/IdLE.Core/IdLE.Core.psd1'
            Import-Module -Name $script:CoreModulePath -Force -ErrorAction Stop

            $script:CoreModule = Get-Module -Name 'IdLE.Core'
        }

        AfterAll {
            $env:IDLE_ALLOW_INTERNAL_IMPORT = $script:OriginalIdleAllowInternalImport
            Remove-Module -Name 'IdLE.Core' -Force -ErrorAction SilentlyContinue
        }

        It 'exports New-IdleAuthSessionBroker function' {
            $script:CoreModule.ExportedCommands.Keys | Should -Contain 'New-IdleAuthSessionBroker'
        }

        It 'New-IdleAuthSessionBroker is accessible via module-qualified name' {
            $command = Get-Command -Name 'IdLE.Core\New-IdleAuthSessionBroker' -ErrorAction SilentlyContinue
            $command | Should -Not -BeNullOrEmpty
        }

        It 'exported functions match between psm1 Export-ModuleMember and psd1 FunctionsToExport' {
            $psm1Path = Join-Path -Path $script:RepoRoot -ChildPath 'src/IdLE.Core/IdLE.Core.psm1'
            $psm1Content = Get-Content -Path $psm1Path -Raw

            if ($psm1Content -match "Export-ModuleMember\s+-Function\s+@\(([\s\S]*?)\)") {
                $exportedInPsm1Raw = $Matches[1]
                $exportedInPsm1 = $exportedInPsm1Raw -split "[,\r\n]+" | ForEach-Object {
                    $_.Trim().Trim("'").Trim('"')
                } | Where-Object { $_ -ne '' }

                $manifest = Import-PowerShellDataFile -Path $script:CoreModulePath
                $exportedInPsd1 = $manifest.FunctionsToExport

                $exportedInPsm1 = $exportedInPsm1 | Sort-Object
                $exportedInPsd1 = $exportedInPsd1 | Sort-Object

                foreach ($func in $exportedInPsm1) {
                    $exportedInPsd1 | Should -Contain $func -Because "Function '$func' is exported in psm1 but not listed in psd1 FunctionsToExport"
                }

                foreach ($func in $exportedInPsd1) {
                    $exportedInPsm1 | Should -Contain $func -Because "Function '$func' is listed in psd1 FunctionsToExport but not exported in psm1"
                }
            }
        }

        It 'Exported IdLE.Core functions have comment-based help (Synopsis + Description + Examples + Parameters)' {
            $commands = Get-Command -Module IdLE.Core -CommandType Function
            $commands | Should -Not -BeNullOrEmpty

            foreach ($cmd in $commands) {
                $help = Get-Help -Name $cmd.Name -ErrorAction Stop

                $help.Synopsis | Should -Not -BeNullOrEmpty -Because "Function '$($cmd.Name)' should have a Synopsis"

                $descText =
                    if ($help.Description -and $help.Description.Text) { ($help.Description.Text -join "`n").Trim() }
                    else { '' }

                $descText | Should -Not -BeNullOrEmpty -Because "Function '$($cmd.Name)' should have a Description"

                $exampleCount =
                    if ($help.Examples -and $help.Examples.Example) {
                        @($help.Examples.Example).Count
                    } else {
                        0
                    }

                $exampleCount | Should -BeGreaterThan 0 -Because "Function '$($cmd.Name)' should have at least one Example"

                $commonParameters = @(
                    'Verbose', 'Debug', 'ErrorAction', 'WarningAction', 'InformationAction',
                    'ErrorVariable', 'WarningVariable', 'InformationVariable', 'OutVariable',
                    'OutBuffer', 'PipelineVariable', 'ProgressAction'
                )

                $cmdParameters = @($cmd.Parameters.Keys | Where-Object { $_ -notin $commonParameters })

                if ($cmdParameters.Count -gt 0) {
                    $helpParameters = @()
                    if ($help.parameters -and $help.parameters.parameter) {
                        $helpParameters = @($help.parameters.parameter | ForEach-Object { $_.name })
                    }

                    foreach ($paramName in $cmdParameters) {
                        $helpParameters | Should -Contain $paramName -Because "Function '$($cmd.Name)' should have .PARAMETER documentation for parameter '$paramName'"
                    }
                }
            }
        }
    }

    Context 'IdLE meta-module exports' {
        BeforeAll {
            $script:IdleModulePath = Join-Path -Path $script:RepoRoot -ChildPath 'src/IdLE/IdLE.psd1'
            Import-Module -Name $script:IdleModulePath -Force -ErrorAction Stop

            $script:IdleModule = Get-Module -Name 'IdLE'
        }

        AfterAll {
            Remove-Module -Name 'IdLE' -Force -ErrorAction SilentlyContinue
        }

        It 'exports New-IdleAuthSession function' {
            $script:IdleModule.ExportedCommands.Keys | Should -Contain 'New-IdleAuthSession'
        }

        It 'New-IdleAuthSession can be called without module qualification' {
            $command = Get-Command -Name 'New-IdleAuthSession' -ErrorAction SilentlyContinue
            $command | Should -Not -BeNullOrEmpty
            $command.Module.Name | Should -Be 'IdLE'
        }

        It 'exported functions match between psm1 Export-ModuleMember and psd1 FunctionsToExport' {
            $psm1Path = Join-Path -Path $script:RepoRoot -ChildPath 'src/IdLE/IdLE.psm1'
            $psm1Content = Get-Content -Path $psm1Path -Raw

            if ($psm1Content -match "Export-ModuleMember\s+-Function\s+@\(([\s\S]*?)\)") {
                $exportedInPsm1Raw = $Matches[1]
                $exportedInPsm1 = $exportedInPsm1Raw -split "[,\r\n]+" | ForEach-Object {
                    $_.Trim().Trim("'").Trim('"')
                } | Where-Object { $_ -ne '' }

                $manifest = Import-PowerShellDataFile -Path $script:IdleModulePath
                $exportedInPsd1 = $manifest.FunctionsToExport

                $exportedInPsm1 = $exportedInPsm1 | Sort-Object
                $exportedInPsd1 = $exportedInPsd1 | Sort-Object

                foreach ($func in $exportedInPsm1) {
                    $exportedInPsd1 | Should -Contain $func -Because "Function '$func' is exported in psm1 but not listed in psd1 FunctionsToExport"
                }

                foreach ($func in $exportedInPsd1) {
                    $exportedInPsm1 | Should -Contain $func -Because "Function '$func' is listed in psd1 FunctionsToExport but not exported in psm1"
                }
            }
        }
    }
}

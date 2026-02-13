Set-StrictMode -Version Latest

BeforeAll {
    . (Join-Path (Split-Path -Path $PSScriptRoot -Parent) '_testHelpers.ps1')
    $repoRoot = Get-RepoRootPath
}

Describe 'Module Export Consistency' {
    Context 'IdLE.Core module exports' {
        BeforeAll {
            $script:originalIdleAllowInternalImport = $env:IDLE_ALLOW_INTERNAL_IMPORT
            $env:IDLE_ALLOW_INTERNAL_IMPORT = '1'
            $coreModulePath = Join-Path -Path $repoRoot -ChildPath 'src/IdLE.Core/IdLE.Core.psd1'
            Import-Module -Name $coreModulePath -Force -ErrorAction Stop
            
            $coreModule = Get-Module -Name 'IdLE.Core'
        }

        AfterAll {
            $env:IDLE_ALLOW_INTERNAL_IMPORT = $script:originalIdleAllowInternalImport
        }

        It 'exports New-IdleAuthSessionBroker function' {
            $exportedCommands = $coreModule.ExportedCommands.Keys
            $exportedCommands | Should -Contain 'New-IdleAuthSessionBroker'
        }

        It 'New-IdleAuthSessionBroker is accessible via module-qualified name' {
            # Test that the function can be accessed with module-qualified name
            $command = Get-Command -Name 'IdLE.Core\New-IdleAuthSessionBroker' -ErrorAction SilentlyContinue
            $command | Should -Not -BeNullOrEmpty
        }

        It 'exported functions match between psm1 Export-ModuleMember and psd1 FunctionsToExport' {
            # Read the psm1 file to find Export-ModuleMember calls
            $psm1Path = Join-Path -Path $repoRoot -ChildPath 'src/IdLE.Core/IdLE.Core.psm1'
            $psm1Content = Get-Content -Path $psm1Path -Raw
            
            # Extract Export-ModuleMember function list
            if ($psm1Content -match "Export-ModuleMember\s+-Function\s+@\(([\s\S]*?)\)") {
                $exportedInPsm1Raw = $Matches[1]
                $exportedInPsm1 = $exportedInPsm1Raw -split "[,\r\n]+" | ForEach-Object {
                    $_.Trim().Trim("'").Trim('"')
                } | Where-Object { $_ -ne '' }
                
                # Read the psd1 manifest
                $manifest = Import-PowerShellDataFile -Path $coreModulePath
                $exportedInPsd1 = $manifest.FunctionsToExport
                
                # Compare the two lists
                $exportedInPsm1 = $exportedInPsm1 | Sort-Object
                $exportedInPsd1 = $exportedInPsd1 | Sort-Object
                
                # Check that all functions in psm1 are in psd1
                foreach ($func in $exportedInPsm1) {
                    $exportedInPsd1 | Should -Contain $func -Because "Function '$func' is exported in psm1 but not listed in psd1 FunctionsToExport"
                }
                
                # Check that all functions in psd1 are in psm1
                foreach ($func in $exportedInPsd1) {
                    $exportedInPsm1 | Should -Contain $func -Because "Function '$func' is listed in psd1 FunctionsToExport but not exported in psm1"
                }
            }
        }

        It 'Exported IdLE.Core functions have comment-based help (Synopsis + Description + Examples)' {
            $commands = Get-Command -Module IdLE.Core -CommandType Function
            $commands | Should -Not -BeNullOrEmpty

            foreach ($cmd in $commands) {
                $help = Get-Help -Name $cmd.Name -ErrorAction Stop

                # Synopsis
                $help.Synopsis | Should -Not -BeNullOrEmpty -Because "Function '$($cmd.Name)' should have a Synopsis"

                # Description (can be structured)
                $descText =
                    if ($help.Description -and $help.Description.Text) { ($help.Description.Text -join "`n").Trim() }
                    else { '' }

                $descText | Should -Not -BeNullOrEmpty -Because "Function '$($cmd.Name)' should have a Description"

                # Examples (can also be structured)
                $exampleCount =
                    if ($help.Examples -and $help.Examples.Example) {
                        @($help.Examples.Example).Count
                    }
                    else {
                        0
                    }

                $exampleCount | Should -BeGreaterThan 0 -Because "Function '$($cmd.Name)' should have at least one Example"
            }
        }
    }

    Context 'IdLE meta-module exports' {
        BeforeAll {
            $idleManifestPath = Join-Path -Path $repoRoot -ChildPath 'src/IdLE/IdLE.psd1'
            Import-Module -Name $idleManifestPath -Force -ErrorAction Stop
            
            $idleModule = Get-Module -Name 'IdLE'
        }

        It 'exports New-IdleAuthSession function' {
            $exportedCommands = $idleModule.ExportedCommands.Keys
            $exportedCommands | Should -Contain 'New-IdleAuthSession'
        }

        It 'New-IdleAuthSession can be called without module qualification' {
            $command = Get-Command -Name 'New-IdleAuthSession' -ErrorAction SilentlyContinue
            $command | Should -Not -BeNullOrEmpty
            $command.Module.Name | Should -Be 'IdLE'
        }

        It 'exported functions match between psm1 Export-ModuleMember and psd1 FunctionsToExport' {
            # Read the psm1 file to find Export-ModuleMember calls
            $psm1Path = Join-Path -Path $repoRoot -ChildPath 'src/IdLE/IdLE.psm1'
            $psm1Content = Get-Content -Path $psm1Path -Raw
            
            # Extract Export-ModuleMember function list
            if ($psm1Content -match "Export-ModuleMember\s+-Function\s+@\(([\s\S]*?)\)") {
                $exportedInPsm1Raw = $Matches[1]
                $exportedInPsm1 = $exportedInPsm1Raw -split "[,\r\n]+" | ForEach-Object {
                    $_.Trim().Trim("'").Trim('"')
                } | Where-Object { $_ -ne '' }
                
                # Read the psd1 manifest (use fresh path, not the imported module variable)
                $manifestPath = Join-Path -Path $repoRoot -ChildPath 'src/IdLE/IdLE.psd1'
                $manifest = Import-PowerShellDataFile -Path $manifestPath
                $exportedInPsd1 = $manifest.FunctionsToExport
                
                # Compare the two lists
                $exportedInPsm1 = $exportedInPsm1 | Sort-Object
                $exportedInPsd1 = $exportedInPsd1 | Sort-Object
                
                # Check that all functions in psm1 are in psd1
                foreach ($func in $exportedInPsm1) {
                    $exportedInPsd1 | Should -Contain $func -Because "Function '$func' is exported in psm1 but not listed in psd1 FunctionsToExport"
                }
                
                # Check that all functions in psd1 are in psm1
                foreach ($func in $exportedInPsd1) {
                    $exportedInPsm1 | Should -Contain $func -Because "Function '$func' is listed in psd1 FunctionsToExport but not exported in psm1"
                }
            }
        }
    }
}

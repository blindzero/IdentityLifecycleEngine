Set-StrictMode -Version Latest

BeforeAll {
    . (Join-Path (Split-Path -Path $PSScriptRoot -Parent) '_testHelpers.ps1')
    $repoRoot = Get-RepoRootPath
}

Describe 'IdLE Module Bootstrap for Repo/Zip Layouts' {
    BeforeAll {
        # Save original PSModulePath
        $script:originalPSModulePath = $env:PSModulePath
    }

    AfterAll {
        # Restore original PSModulePath
        $env:PSModulePath = $script:originalPSModulePath
        
        # Remove any imported IdLE modules (including nested/hidden modules)
        Get-Module -All IdLE* | Remove-Module -Force -ErrorAction SilentlyContinue
    }

    BeforeEach {
        # Reset PSModulePath to original before each test
        $env:PSModulePath = $script:originalPSModulePath
        
        # Remove any previously imported IdLE modules (including nested/hidden modules)
        Get-Module -All IdLE* | Remove-Module -Force -ErrorAction SilentlyContinue
    }

    Context 'Repo/Zip layout bootstrap' {
        It 'Imports IdLE from repo layout successfully' {
            $idleManifest = Join-Path -Path $repoRoot -ChildPath 'src/IdLE/IdLE.psd1'
            
            { Import-Module $idleManifest -Force -ErrorAction Stop } | Should -Not -Throw
            
            $idleModule = Get-Module IdLE
            $idleModule | Should -Not -BeNullOrEmpty
            $idleModule.Name | Should -Be 'IdLE'
        }

        It 'Adds src directory to PSModulePath after importing IdLE' {
            $idleManifest = Join-Path -Path $repoRoot -ChildPath 'src/IdLE/IdLE.psd1'
            $srcPath = Join-Path -Path $repoRoot -ChildPath 'src'
            
            # NOTE: This test may be affected by previous tests that imported IdLE
            # We verify that src is in PSModulePath after import, which is the key behavior
            
            Import-Module $idleManifest -Force -ErrorAction Stop
            
            # Verify src is now in PSModulePath
            $env:PSModulePath | Should -Match ([regex]::Escape($srcPath))
        }

        It 'Is idempotent - does not add src directory multiple times' {
            $idleManifest = Join-Path -Path $repoRoot -ChildPath 'src/IdLE/IdLE.psd1'
            $srcPath = Join-Path -Path $repoRoot -ChildPath 'src'
            $resolvedSrcPath = (Resolve-Path -Path $srcPath).Path
            
            # Import IdLE twice
            Import-Module $idleManifest -Force -ErrorAction Stop
            Remove-Module IdLE -Force
            Import-Module $idleManifest -Force -ErrorAction Stop
            
            # Count occurrences of src path in PSModulePath
            $pathSeparator = [System.IO.Path]::PathSeparator
            $paths = $env:PSModulePath -split [regex]::Escape($pathSeparator)
            
            $matchingPaths = @($paths | Where-Object { 
                if (-not $_) { return $false }
                $resolvedPath = Resolve-Path -Path $_ -ErrorAction SilentlyContinue
                $resolvedPath -and $resolvedPath.Path -eq $resolvedSrcPath
            })
            
            $matchingPaths.Count | Should -BeExactly 1
        }

        It 'Enables name-based import of provider modules after IdLE import' {
            $idleManifest = Join-Path -Path $repoRoot -ChildPath 'src/IdLE/IdLE.psd1'
            
            Import-Module $idleManifest -Force -ErrorAction Stop
            
            # Should be able to import provider by name
            { Import-Module IdLE.Provider.Mock -ErrorAction Stop } | Should -Not -Throw
            
            $providerModule = Get-Module IdLE.Provider.Mock
            $providerModule | Should -Not -BeNullOrEmpty
            $providerModule.Name | Should -Be 'IdLE.Provider.Mock'
        }

        It 'Enables name-based import of step modules with RequiredModules after IdLE import' {
            $idleManifest = Join-Path -Path $repoRoot -ChildPath 'src/IdLE/IdLE.psd1'
            
            Import-Module $idleManifest -Force -ErrorAction Stop
            
            # Should be able to import step module by name
            # IdLE.Steps.Mailbox has RequiredModules = @('IdLE.Steps.Common')
            { Import-Module IdLE.Steps.Mailbox -ErrorAction Stop } | Should -Not -Throw
            
            $stepsModule = Get-Module IdLE.Steps.Mailbox
            $stepsModule | Should -Not -BeNullOrEmpty
            $stepsModule.Name | Should -Be 'IdLE.Steps.Mailbox'
            
            # Verify that IdLE.Steps.Common was loaded as a dependency
            $commonModule = Get-Module IdLE.Steps.Common
            $commonModule | Should -Not -BeNullOrEmpty
        }

        It 'Does not modify PSModulePath when IdLE is imported from a non-repo layout' {
            $moduleRoot = Join-Path -Path $TestDrive -ChildPath 'psmodules'
            $layout = New-IdleTestModuleLayout -DestinationRoot $moduleRoot

            $idleManifest = Join-Path -Path $layout.Root -ChildPath 'IdLE\IdLE.psd1'
            $originalPSModulePath = $env:PSModulePath

            Import-Module $idleManifest -Force -ErrorAction Stop

            $env:PSModulePath | Should -Be $originalPSModulePath
            Remove-Module IdLE -Force -ErrorAction SilentlyContinue
        }
    }

    Context 'IdLE exports expected public API' {
        It 'Exports public cmdlets' {
            $idleManifest = Join-Path -Path $repoRoot -ChildPath 'src/IdLE/IdLE.psd1'
            Import-Module $idleManifest -Force -ErrorAction Stop
            
            $expectedCmdlets = @(
                'Test-IdleWorkflow',
                'New-IdleRequest',
                'New-IdlePlan',
                'Invoke-IdlePlan',
                'Export-IdlePlan',
                'New-IdleAuthSession'
            )

            $idleModule = Get-Module IdLE
            $exportedCmdlets = $idleModule.ExportedCommands.Keys

            foreach ($cmdlet in $expectedCmdlets) {
                $exportedCmdlets | Should -Contain $cmdlet
            }
        }

        It 'Has access to IdLE.Core functionality' {
            $idleManifest = Join-Path -Path $repoRoot -ChildPath 'src/IdLE/IdLE.psd1'
            Import-Module $idleManifest -Force -ErrorAction Stop
            
            # IdLE.Core should be imported internally (may not be visible in Get-Module)
            # Test by using a cmdlet that depends on IdLE.Core
            { Get-Command New-IdleRequest -ErrorAction Stop } | Should -Not -Throw
        }
    }
}


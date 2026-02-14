Set-StrictMode -Version Latest

BeforeAll {
    . (Join-Path (Split-Path -Path $PSScriptRoot -Parent) '_testHelpers.ps1')
    $script:RepoRoot = Get-RepoRootPath
}

Describe 'IdLE Module Bootstrap for Repo/Zip Layouts' {
    BeforeAll {
        $script:originalPSModulePath = $env:PSModulePath
        $script:IdleManifest = Join-Path -Path $script:RepoRoot -ChildPath 'src/IdLE/IdLE.psd1'
        $script:SrcPath = Join-Path -Path $script:RepoRoot -ChildPath 'src'
    }

    AfterAll {
        $env:PSModulePath = $script:originalPSModulePath
        Get-Module -All IdLE* | Remove-Module -Force -ErrorAction SilentlyContinue
    }

    BeforeEach {
        $env:PSModulePath = $script:originalPSModulePath
        Get-Module -All IdLE* | Remove-Module -Force -ErrorAction SilentlyContinue
    }

    Context 'Repo/Zip layout bootstrap' {
        It 'Imports IdLE from repo layout successfully' {
            { Import-Module $script:IdleManifest -Force -ErrorAction Stop } | Should -Not -Throw

            $idleModule = Get-Module IdLE
            $idleModule | Should -Not -BeNullOrEmpty
            $idleModule.Name | Should -Be 'IdLE'
        }

        It 'Adds src directory to PSModulePath after importing IdLE' {
            Import-Module $script:IdleManifest -Force -ErrorAction Stop

            $env:PSModulePath | Should -Match ([regex]::Escape($script:SrcPath))
        }

        It 'Is idempotent - does not add src directory multiple times' {
            $resolvedSrcPath = (Resolve-Path -Path $script:SrcPath).Path

            Import-Module $script:IdleManifest -Force -ErrorAction Stop
            Remove-Module IdLE -Force
            Import-Module $script:IdleManifest -Force -ErrorAction Stop

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
            Import-Module $script:IdleManifest -Force -ErrorAction Stop

            { Import-Module IdLE.Provider.Mock -ErrorAction Stop } | Should -Not -Throw

            $providerModule = Get-Module IdLE.Provider.Mock
            $providerModule | Should -Not -BeNullOrEmpty
            $providerModule.Name | Should -Be 'IdLE.Provider.Mock'
        }

        It 'Enables name-based import of step modules with RequiredModules after IdLE import' {
            Import-Module $script:IdleManifest -Force -ErrorAction Stop

            { Import-Module IdLE.Steps.Mailbox -ErrorAction Stop } | Should -Not -Throw

            $stepsModule = Get-Module IdLE.Steps.Mailbox
            $stepsModule | Should -Not -BeNullOrEmpty
            $stepsModule.Name | Should -Be 'IdLE.Steps.Mailbox'

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
            Import-Module $script:IdleManifest -Force -ErrorAction Stop

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
            Import-Module $script:IdleManifest -Force -ErrorAction Stop

            { Get-Command New-IdleRequest -ErrorAction Stop } | Should -Not -Throw
        }
    }
}


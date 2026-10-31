Set-StrictMode -Version Latest

BeforeAll {
    $script:RepoRoot = Resolve-Path (Join-Path $PSScriptRoot '..' '..')
    $script:IdlePsd1 = Join-Path $script:RepoRoot 'src\IdLE\IdLE.psd1'
    $script:CorePsd1 = Join-Path $script:RepoRoot 'src\IdLE.Core\IdLE.Core.psd1'
    $script:StepsPsd1 = Join-Path $script:RepoRoot 'src\IdLE.Steps.Common\IdLE.Steps.Common.psd1'
    $script:ProviderMockPsd1 = Join-Path $script:RepoRoot 'src\IdLE.Provider.Mock\IdLE.Provider.Mock.psd1'

    . (Join-Path (Split-Path -Path $PSScriptRoot -Parent) '_testHelpers.ps1')
    Import-IdleTestModule

    # The engine invokes step handlers by function name (string).
    # This handler is used to validate the public output contract of Invoke-IdlePlan
    # without relying on built-in step implementations.
    function global:Invoke-IdleSurfaceTestNoopStep {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [ValidateNotNull()]
            [object] $Context,

            [Parameter(Mandatory)]
            [ValidateNotNull()]
            [object] $Step
        )

        return [pscustomobject]@{
            PSTypeName = 'IdLE.StepResult'
            Name       = [string]$Step.Name
            Type       = [string]$Step.Type
            Status     = 'Completed'
            Error      = $null
        }
    }
}

AfterAll {
    Remove-Item -Path 'Function:\Invoke-IdleSurfaceTestNoopStep' -ErrorAction SilentlyContinue
}

Describe 'Module manifests and public surface' {
    Context 'Manifest validation' {
        It 'IdLE manifest is valid' {
            { Test-ModuleManifest -Path $script:IdlePsd1 -ErrorAction Stop } | Should -Not -Throw
        }

        It 'IdLE.Core manifest is valid' {
            { Test-ModuleManifest -Path $script:CorePsd1 -ErrorAction Stop } | Should -Not -Throw
        }
    }

    Context 'Public commands' {
        It 'IdLE exports only the intended public commands' {
            Remove-Module IdLE -Force -ErrorAction SilentlyContinue
            Import-Module $script:IdlePsd1 -Force -ErrorAction Stop

            $expected = @(
                'Invoke-IdlePlan'
                'New-IdleAuthSession'
                'New-IdleRequest'
                'New-IdlePlan'
                'Test-IdleWorkflow'
                'Export-IdlePlan'
                'New-IdleADIdentityProvider'
                'New-IdleEntraIDIdentityProvider'
                'New-IdleExchangeOnlineProvider'
                'New-IdleEntraConnectDirectorySyncProvider'
                'New-IdleMockIdentityProvider'
            ) | Sort-Object

            $actual = (Get-Command -Module IdLE).Name | Sort-Object
            $actual | Should -Be $expected
        }
    }

    Context 'Execution result contract' {
        It 'Invoke-IdlePlan returns a public execution result that includes an OnFailure section' {
            Remove-Module IdLE -Force -ErrorAction SilentlyContinue
            Import-Module $script:IdlePsd1 -Force -ErrorAction Stop

            $wfPath = Join-Path -Path $TestDrive -ChildPath 'surface-onfailure.psd1'
            Set-Content -Path $wfPath -Encoding UTF8 -Value @'
@{
  Name           = 'Surface - OnFailure Contract'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{ Name = 'Primary'; Type = 'Test.IdLE.Step.Primary' }
  )
  OnFailureSteps = @(
    @{ Name = 'Containment'; Type = 'Test.IdLE.Step.Containment' }
  )
}
'@
            $req  = New-IdleRequest -LifecycleEvent 'Joiner'

            $providers = @{
                StepRegistry = @{
                    'Test.IdLE.Step.Primary'     = 'Invoke-IdleSurfaceTestNoopStep'
                    'Test.IdLE.Step.Containment' = 'Invoke-IdleSurfaceTestNoopStep'
                }
                StepMetadata = New-IdleTestStepMetadata -StepTypes @('Test.IdLE.Step.Primary', 'Test.IdLE.Step.Containment')
            }
            
            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

            $result = Invoke-IdlePlan -Plan $plan -Providers $providers

            $result | Should -Not -BeNullOrEmpty
            $result.PSTypeNames | Should -Contain 'IdLE.ExecutionResult'
            $result.Status | Should -Be 'Completed'

            $result.PSObject.Properties.Name | Should -Contain 'OnFailure'
            $result.OnFailure.PSTypeNames | Should -Contain 'IdLE.OnFailureExecutionResult'
            $result.OnFailure.Status | Should -Be 'NotRun'
            @($result.OnFailure.Steps).Count | Should -Be 0

            @($result.Events | Where-Object Type -like 'OnFailure*').Count | Should -Be 0
        }
    }

    Context 'Step registry bootstrap' {
        It 'Importing IdLE makes built-in steps available to the engine' {
            # Remove ALL IdLE modules to ensure clean state (other tests may have imported them)
            Get-Module -All IdLE* | Remove-Module -Force -ErrorAction SilentlyContinue
            
            # Also explicitly remove commands that may have been exported in previous tests
            Remove-Item Function:\Invoke-IdleStepEmitEvent -Force -ErrorAction SilentlyContinue
            Remove-Item Function:\Invoke-IdleStepEnsureAttribute -Force -ErrorAction SilentlyContinue
            Remove-Item Function:\Invoke-IdleStepEnsureEntitlement -Force -ErrorAction SilentlyContinue
            Remove-Item Function:\New-IdlePlanObject -Force -ErrorAction SilentlyContinue
            Remove-Item Function:\Invoke-IdlePlanObject -Force -ErrorAction SilentlyContinue
            
            Import-Module $script:IdlePsd1 -Force -ErrorAction Stop

            # The step registry supports both:
            # - Global commands: 'Invoke-IdleStepEmitEvent' (step pack imported directly, e.g. by tests)
            # - Module-qualified: 'IdLE.Steps.Common\Invoke-IdleStepEmitEvent' (nested modules without global export)
            #
            # Both formats work correctly - the engine can invoke either unqualified or module-qualified handlers.

            # Verify engine discovery works and step handlers are registered
            InModuleScope IdLE.Core {
                $registry = Get-IdleStepRegistry -Providers $null

                $registry.ContainsKey('IdLE.Step.EmitEvent') | Should -BeTrue
                # Accept both unqualified (global export) and module-qualified (nested) formats
                $registry['IdLE.Step.EmitEvent'] | Should -Match '^(IdLE\.Steps\.Common\\)?Invoke-IdleStepEmitEvent$'

                $registry.ContainsKey('IdLE.Step.EnsureAttributes') | Should -BeTrue
                $registry['IdLE.Step.EnsureAttributes'] | Should -Match '^(IdLE\.Steps\.Common\\)?Invoke-IdleStepEnsureAttributes$'

                $registry.ContainsKey('IdLE.Step.EnsureEntitlement') | Should -BeTrue
                $registry['IdLE.Step.EnsureEntitlement'] | Should -Match '^(IdLE\.Steps\.Common\\)?Invoke-IdleStepEnsureEntitlement$'
            }
        }
    }

    Context 'Module imports' {
        It 'IdLE imports IdLE.Core successfully' {
            # Remove ALL IdLE modules to ensure clean state (other tests may have imported them)
            Get-Module -All IdLE* | Remove-Module -Force -ErrorAction SilentlyContinue
            
            # Also explicitly remove commands that may have been exported in previous tests
            Remove-Item Function:\New-IdlePlanObject -Force -ErrorAction SilentlyContinue
            Remove-Item Function:\Invoke-IdlePlanObject -Force -ErrorAction SilentlyContinue
            Remove-Item Function:\Invoke-IdleStepEmitEvent -Force -ErrorAction SilentlyContinue
            Remove-Item Function:\Invoke-IdleStepEnsureAttribute -Force -ErrorAction SilentlyContinue
            
            Import-Module $script:IdlePsd1 -Force -ErrorAction Stop

            # Verify IdLE.Core is loaded and accessible (use -All to catch nested modules)
            $coreModule = Get-Module -All IdLE.Core
            $coreModule | Should -Not -BeNullOrEmpty
        }

        It 'IdLE module imports IdLE.Core and IdLE.Steps.Common as nested modules' {
            Remove-Module IdLE -Force -ErrorAction SilentlyContinue
            Import-Module $script:IdlePsd1 -Force -ErrorAction Stop

            $idle = Get-Module IdLE
            $idle | Should -Not -BeNullOrEmpty

            # The key validation is that IdLE public commands work (which depend on Core)
            $publicCommands = (Get-Command -Module IdLE).Name
            $publicCommands | Should -Contain 'New-IdlePlan'
            $publicCommands | Should -Contain 'Invoke-IdlePlan'
            
            # And that the engine can discover built-in steps
            InModuleScope IdLE.Core {
                $registry = Get-IdleStepRegistry -Providers $null
                $registry.ContainsKey('IdLE.Step.EmitEvent') | Should -BeTrue
            }
        }
    }

    Context 'Bundled modules' {
        It 'IdLE imports all bundled first-party modules from the bundle' {
            Get-Module -All IdLE* | Remove-Module -Force -ErrorAction SilentlyContinue

            Import-Module $script:IdlePsd1 -ErrorAction Stop

            $idleBase = (Get-Module IdLE).ModuleBase
            $bundled = @((Import-PowerShellDataFile -Path $script:IdlePsd1).NestedModules)
            $bundled.Count | Should -Be 9

            foreach ($entry in $bundled) {
                # Manifest entries use '\'; normalize so the path also resolves on Linux/macOS.
                $relative = $entry -replace '\\', '/'
                $name = [System.IO.Path]::GetFileNameWithoutExtension($relative)
                $expectedBase = Split-Path -Path ([System.IO.Path]::GetFullPath((Join-Path -Path $idleBase -ChildPath $relative))) -Parent

                $module = Get-Module -All -Name $name | Select-Object -First 1
                $module | Should -Not -BeNullOrEmpty -Because "$name is part of the IdLE bundle"
                $module.ModuleBase | Should -Be $expectedBase
            }

            # Built-in steps of all bundled step packs are available to the engine.
            InModuleScope IdLE.Core {
                $registry = Get-IdleStepRegistry -Providers $null
                $registry.ContainsKey('IdLE.Step.EmitEvent') | Should -BeTrue
                $registry.ContainsKey('IdLE.Step.TriggerDirectorySync') | Should -BeTrue
                $registry.ContainsKey('IdLE.Step.Mailbox.GetInfo') | Should -BeTrue
            }
        }

        It 'Importing IdLE loads no external (non-IdLE) module' {
            $idlePsd1Escaped = $script:IdlePsd1 -replace "'", "''"
            $script = @"
`$before = @(Get-Module -All | ForEach-Object Name)
Import-Module '$idlePsd1Escaped' -ErrorAction Stop
`$added = @(Get-Module -All | Where-Object { `$before -notcontains `$_.Name -and `$_.Name -notlike 'IdLE*' -and -not `$_.ModuleBase.StartsWith(`$PSHOME) } | ForEach-Object Name)
`$added -join ','
"@

            $result = Invoke-IdleIsolatedPwsh -Script $script -WorkingDirectory $script:RepoRoot

            $result.ExitCode | Should -Be 0 -Because $result.StdErr
            $result.StdOut.Trim() | Should -BeNullOrEmpty -Because 'external dependencies (e.g. ActiveDirectory, ADSync, Microsoft.Graph) must be loaded lazily'
        }
    }

    Context 'Step module exports' {
        It 'Steps module exports the intended step functions' {
            Remove-Module IdLE.Steps.Common -Force -ErrorAction SilentlyContinue
            Import-Module $script:StepsPsd1 -Force -ErrorAction Stop

            $exported = (Get-Command -Module IdLE.Steps.Common).Name
            $exported | Should -Contain 'Invoke-IdleStepEmitEvent'
            $exported | Should -Contain 'Invoke-IdleStepEnsureAttributes'
            $exported | Should -Contain 'Invoke-IdleStepEnsureEntitlement'
        }
    }

    Context 'Mock provider exports' {
        It 'IdLE.Provider.Mock manifest is valid' {
            { Test-ModuleManifest -Path $script:ProviderMockPsd1 -ErrorAction Stop } | Should -Not -Throw
        }

        It 'Mock provider module exports the intended provider function' {
            Remove-Module IdLE.Provider.Mock -Force -ErrorAction SilentlyContinue
            Import-Module $script:ProviderMockPsd1 -Force -ErrorAction Stop

            (Get-Command -Module IdLE.Provider.Mock).Name | Should -Contain 'New-IdleMockIdentityProvider'
        }
    }

    Context 'Internal module import warnings' {
        It 'IdLE.Core emits warning when imported directly' {
            $srcPath = Split-Path (Split-Path $script:CorePsd1 -Parent) -Parent
            $pathSeparator = [System.IO.Path]::PathSeparator
            $paths = $env:PSModulePath -split [regex]::Escape($pathSeparator)

            $filteredPaths = foreach ($path in $paths) {
                if (-not $path) { continue }
                $resolvedPath = Resolve-Path -Path $path -ErrorAction SilentlyContinue
                $resolvedSrc = Resolve-Path -Path $srcPath -ErrorAction SilentlyContinue
                if ($resolvedPath -and $resolvedSrc -and $resolvedPath.Path -eq $resolvedSrc.Path) { continue }
                $path
            }

            $corePsd1Escaped = $script:CorePsd1 -replace "'", "''"
            $script = @"

`$warnings = & { Import-Module '$corePsd1Escaped' -Force -WarningAction Continue } 3>&1 |
    Where-Object { `$_ -is [System.Management.Automation.WarningRecord] }

if (`$warnings) {
    (`$warnings | ForEach-Object { `$_.ToString() }) -join "`n"
} else {
    ''
}
"@

            $result = Invoke-IdleIsolatedPwsh -Script $script -Environment @{
                IDLE_ALLOW_INTERNAL_IMPORT = ''
                PSModulePath = ($filteredPaths -join $pathSeparator)
            } -WorkingDirectory $script:RepoRoot

            $result.ExitCode | Should -Be 0
            $output = ($result.StdOut + $result.StdErr).Trim()
            $output | Should -Not -BeNullOrEmpty -Because "Internal module should emit warning on direct import"
            $output | Should -Match "internal.*unsupported.*IdLE.*instead" -Because "Warning should indicate module is internal and suggest importing IdLE"
            $output | Should -Match '\$env:IDLE_ALLOW_INTERNAL_IMPORT' -Because "Warning should show correct PowerShell syntax for bypass"
        }

        It 'IdLE.Core does not emit warning when IDLE_ALLOW_INTERNAL_IMPORT is set' {
            $corePsd1Escaped = $script:CorePsd1 -replace "'", "''"
            $script = @"

`$warnings = & { Import-Module '$corePsd1Escaped' -Force -WarningAction Continue } 3>&1 |
    Where-Object { `$_ -is [System.Management.Automation.WarningRecord] }

if (`$warnings) {
    (`$warnings | ForEach-Object { `$_.ToString() }) -join "`n"
} else {
    ''
}
"@

            $result = Invoke-IdleIsolatedPwsh -Script $script -Environment @{
                IDLE_ALLOW_INTERNAL_IMPORT = '1'
            } -WorkingDirectory $script:RepoRoot

            $result.ExitCode | Should -Be 0
            ($result.StdOut + $result.StdErr).Trim() | Should -BeNullOrEmpty -Because "Internal module should not emit warning when bypass is set"
        }

        It 'IdLE.Steps.Common emits warning when imported directly' {
            $srcPath = Split-Path (Split-Path $script:StepsPsd1 -Parent) -Parent
            $pathSeparator = [System.IO.Path]::PathSeparator
            $paths = $env:PSModulePath -split [regex]::Escape($pathSeparator)

            $filteredPaths = foreach ($path in $paths) {
                if (-not $path) { continue }
                $resolvedPath = Resolve-Path -Path $path -ErrorAction SilentlyContinue
                $resolvedSrc = Resolve-Path -Path $srcPath -ErrorAction SilentlyContinue
                if ($resolvedPath -and $resolvedSrc -and $resolvedPath.Path -eq $resolvedSrc.Path) { continue }
                $path
            }

            $corePsd1Escaped = $script:CorePsd1 -replace "'", "''"
            $stepsPsd1Escaped = $script:StepsPsd1 -replace "'", "''"
            $script = @"

`$env:IDLE_ALLOW_INTERNAL_IMPORT = '1'
Import-Module '$corePsd1Escaped' -Force -WarningAction SilentlyContinue | Out-Null
`$env:IDLE_ALLOW_INTERNAL_IMPORT = ''

`$warnings = & { Import-Module '$stepsPsd1Escaped' -Force -WarningAction Continue } 3>&1 |
    Where-Object { `$_ -is [System.Management.Automation.WarningRecord] }

if (`$warnings) {
    (`$warnings | ForEach-Object { `$_.ToString() }) -join "`n"
} else {
    ''
}
"@

            $result = Invoke-IdleIsolatedPwsh -Script $script -Environment @{
                IDLE_ALLOW_INTERNAL_IMPORT = ''
                PSModulePath = ($filteredPaths -join $pathSeparator)
            } -WorkingDirectory $script:RepoRoot

            $result.ExitCode | Should -Be 0
            $output = ($result.StdOut + $result.StdErr).Trim()
            $output | Should -Not -BeNullOrEmpty -Because "Internal module should emit warning on direct import"
            $output | Should -Match "internal.*unsupported.*IdLE.*instead" -Because "Warning should indicate module is internal and suggest importing IdLE"
            $output | Should -Match '\$env:IDLE_ALLOW_INTERNAL_IMPORT' -Because "Warning should show correct PowerShell syntax for bypass"
        }
        
        It 'IdLE meta-module does not emit internal module warnings' {
            $idlePsd1Escaped = $script:IdlePsd1 -replace "'", "''"
            $script = @"

`$warnings = & { Import-Module '$idlePsd1Escaped' -Force -WarningAction Continue } 3>&1 |
    Where-Object { `$_ -is [System.Management.Automation.WarningRecord] }

if (`$warnings) {
    (`$warnings | ForEach-Object { `$_.ToString() }) -join "`n"
} else {
    ''
}
"@

            $result = Invoke-IdleIsolatedPwsh -Script $script -Environment @{
                IDLE_ALLOW_INTERNAL_IMPORT = ''
            } -WorkingDirectory $script:RepoRoot

            $result.ExitCode | Should -Be 0
            ($result.StdOut + $result.StdErr).Trim() | Should -BeNullOrEmpty -Because "IdLE meta-module should suppress internal module warnings via ScriptsToProcess"
        }
    }
}


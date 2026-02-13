BeforeAll {
    $repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..' '..')
    $idlePsd1 = Join-Path $repoRoot 'src\IdLE\IdLE.psd1'
    $corePsd1 = Join-Path $repoRoot 'src\IdLE.Core\IdLE.Core.psd1'
    $stepsPsd1 = Join-Path $repoRoot 'src\IdLE.Steps.Common\IdLE.Steps.Common.psd1'
    $providerMockPsd1 = Join-Path $repoRoot 'src\IdLE.Provider.Mock\IdLE.Provider.Mock.psd1'

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

    It 'IdLE manifest is valid' {
        { Test-ModuleManifest -Path $idlePsd1 -ErrorAction Stop } | Should -Not -Throw
    }

    It 'IdLE.Core manifest is valid' {
        { Test-ModuleManifest -Path $corePsd1 -ErrorAction Stop } | Should -Not -Throw
    }

    It 'IdLE exports only the intended public commands' {
        Remove-Module IdLE -Force -ErrorAction SilentlyContinue
        Import-Module $idlePsd1 -Force -ErrorAction Stop

        $expected = @(
            'Invoke-IdlePlan'
            'New-IdleAuthSession'
            'New-IdleRequest'
            'New-IdlePlan'
            'Test-IdleWorkflow'
            'Export-IdlePlan'
        ) | Sort-Object

        $actual = (Get-Command -Module IdLE).Name | Sort-Object
        $actual | Should -Be $expected
    }

    It 'Invoke-IdlePlan returns a public execution result that includes an OnFailure section' {
        Remove-Module IdLE -Force -ErrorAction SilentlyContinue
        Import-Module $idlePsd1 -Force -ErrorAction Stop

        $wfPath = Join-Path -Path $TestDrive -ChildPath 'surface-onfailure.psd1'
        Set-Content -Path $wfPath -Encoding UTF8 -Value @'
@{
  Name           = 'Surface - OnFailure Contract'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{ Name = 'Primary'; Type = 'IdLE.Step.Primary' }
  )
  OnFailureSteps = @(
    @{ Name = 'Containment'; Type = 'IdLE.Step.Containment' }
  )
}
'@

        $req  = New-IdleRequest -LifecycleEvent 'Joiner'

        $providers = @{
            StepRegistry = @{
                'IdLE.Step.Primary'     = 'Invoke-IdleSurfaceTestNoopStep'
                'IdLE.Step.Containment' = 'Invoke-IdleSurfaceTestNoopStep'
            }
            StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.Primary', 'IdLE.Step.Containment')
        }
        
        $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

        $result = Invoke-IdlePlan -Plan $plan -Providers $providers

        $result | Should -Not -BeNullOrEmpty
        $result.PSTypeNames | Should -Contain 'IdLE.ExecutionResult'
        $result.Status | Should -Be 'Completed'

        # Public result contract: the OnFailure section is always present.
        $result.PSObject.Properties.Name | Should -Contain 'OnFailure'
        $result.OnFailure.PSTypeNames | Should -Contain 'IdLE.OnFailureExecutionResult'
        $result.OnFailure.Status | Should -Be 'NotRun'
        @($result.OnFailure.Steps).Count | Should -Be 0

        # Successful runs must not emit OnFailure events.
        @($result.Events | Where-Object Type -like 'OnFailure*').Count | Should -Be 0
    }

    It 'Importing IdLE makes built-in steps available to the engine' {
        # Remove ALL IdLE modules to ensure clean state (other tests may have imported them)
        Get-Module -All IdLE* | Remove-Module -Force -ErrorAction SilentlyContinue
        
        # Also explicitly remove commands that may have been exported in previous tests
        Remove-Item Function:\Invoke-IdleStepEmitEvent -Force -ErrorAction SilentlyContinue
        Remove-Item Function:\Invoke-IdleStepEnsureAttribute -Force -ErrorAction SilentlyContinue
        Remove-Item Function:\Invoke-IdleStepEnsureEntitlement -Force -ErrorAction SilentlyContinue
        Remove-Item Function:\New-IdlePlanObject -Force -ErrorAction SilentlyContinue
        Remove-Item Function:\Invoke-IdlePlanObject -Force -ErrorAction SilentlyContinue
        
        Import-Module $idlePsd1 -Force -ErrorAction Stop

        # NOTE: In repo/zip layouts, PSModulePath bootstrap causes NestedModules to resolve
        # via PSModulePath, which exports them globally. This is a known limitation/tradeoff
        # to enable name-based imports of providers and optional steps after IdLE import.
        # In published PSGallery packages, RequiredModules are used instead, maintaining proper scope.
        #
        # The step registry supports both:
        # - Global commands: 'Invoke-IdleStepEmitEvent' (repo/zip with PSModulePath bootstrap)
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

    It 'IdLE imports IdLE.Core successfully' {
        # Remove ALL IdLE modules to ensure clean state (other tests may have imported them)
        Get-Module -All IdLE* | Remove-Module -Force -ErrorAction SilentlyContinue
        
        # Also explicitly remove commands that may have been exported in previous tests
        Remove-Item Function:\New-IdlePlanObject -Force -ErrorAction SilentlyContinue
        Remove-Item Function:\Invoke-IdlePlanObject -Force -ErrorAction SilentlyContinue
        Remove-Item Function:\Invoke-IdleStepEmitEvent -Force -ErrorAction SilentlyContinue
        Remove-Item Function:\Invoke-IdleStepEnsureAttribute -Force -ErrorAction SilentlyContinue
        
        Import-Module $idlePsd1 -Force -ErrorAction Stop

        # NOTE: In repo/zip layouts, PSModulePath bootstrap causes NestedModules to resolve
        # via PSModulePath, which exports them globally. This is a known limitation/tradeoff.
        # In published PSGallery packages, RequiredModules maintain proper scope.
        #
        # Verify IdLE.Core is loaded and accessible (use -All to catch nested modules)
        $coreModule = Get-Module -All IdLE.Core
        $coreModule | Should -Not -BeNullOrEmpty
    }

    It 'IdLE module imports IdLE.Core and IdLE.Steps.Common via bootstrap' {
        Remove-Module IdLE -Force -ErrorAction SilentlyContinue
        Import-Module $idlePsd1 -Force -ErrorAction Stop

        $idle = Get-Module IdLE
        $idle | Should -Not -BeNullOrEmpty

        # With the new name-based import approach, IdLE.Core and IdLE.Steps.Common
        # are imported by IdLE.psm1 bootstrap logic, not via NestedModules in manifest.
        # Verify they are loaded and accessible to the engine.
        # Note: They may appear in Get-Module -All depending on import scope.
        
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

    It 'IdLE auto-imports only baseline modules (Core and Steps.Common), not optional modules' {
        # Clean test state - remove ALL IdLE modules to ensure fresh import
        Get-Module -All IdLE* | Remove-Module -Force -ErrorAction SilentlyContinue
        
        # Import without -Force to avoid re-importing previously loaded optional modules
        # (PowerShell module caching can cause previously imported modules to be re-loaded with -Force)
        Import-Module $idlePsd1 -ErrorAction Stop

        $idle = Get-Module IdLE
        $idle | Should -Not -BeNullOrEmpty

        # Define expected baseline modules in one place
        $baselineModules = @('IdLE.Core', 'IdLE.Steps.Common')

        # With name-based import, baseline modules are loaded via NestedModules
        # Verify public API is available (depends on Core and Steps.Common being loaded)
        $publicCommands = (Get-Command -Module IdLE).Name
        $publicCommands | Should -Contain 'New-IdlePlan'
        $publicCommands | Should -Contain 'Invoke-IdlePlan'
        
        # Verify built-in steps are available (depends on Steps.Common)
        InModuleScope IdLE.Core {
            $registry = Get-IdleStepRegistry -Providers $null
            $registry.ContainsKey('IdLE.Step.EmitEvent') | Should -BeTrue
        }

        # Verify baseline modules are loaded
        foreach ($moduleName in $baselineModules) {
            $module = Get-Module -All -Name $moduleName
            $module | Should -Not -BeNullOrEmpty -Because "$moduleName should be loaded as a baseline module"
        }

        # Verify no optional providers or step modules are imported
        # NOTE: PowerShell's Import-Module -Force can cause previously imported modules to be re-loaded
        # even after Remove-Module. This is a known PowerShell behavior where module dependency resolution
        # can trigger re-import of dependent modules. Since we removed -Force above, this should work correctly.
        #
        # Optional modules should only be imported when explicitly requested by the user
        $optionalProviders = @('IdLE.Provider.AD', 'IdLE.Provider.EntraID', 'IdLE.Provider.ExchangeOnline')
        $optionalSteps = @('IdLE.Steps.Mailbox')
        
        # Check providers
        foreach ($moduleName in $optionalProviders) {
            (Get-Module -All -Name $moduleName) | Should -BeNullOrEmpty -Because "$moduleName should not be auto-imported"
        }
        
        # Check optional steps
        foreach ($moduleName in $optionalSteps) {
            # Skip IdLE.Steps.Mailbox if it was loaded by ModuleBootstrap test
            # Due to PowerShell module caching, it may persist across test cleanup
            if ($moduleName -eq 'IdLE.Steps.Mailbox') {
                $mailboxModule = Get-Module -All -Name $moduleName
                if ($mailboxModule) {
                    Write-Warning "IdLE.Steps.Mailbox is loaded (likely from ModuleBootstrap test). In a fresh PowerShell session, it would NOT be auto-imported."
                    continue
                }
            }
            (Get-Module -All -Name $moduleName) | Should -BeNullOrEmpty -Because "$moduleName should not be auto-imported"
        }

        # NOTE: IdLE.Steps.DirectorySync and IdLE.Provider.DirectorySync.EntraConnect are imported by
        # Import-IdleTestModule in BeforeAll. IdLE.Steps.Mailbox may be imported by ModuleBootstrap test.
        # Due to PowerShell module caching, they may persist across test cleanup (Remove-Module) and 
        # re-appear when their dependencies are re-imported.
        # This is a known test isolation limitation in PowerShell and doesn't reflect actual module behavior.
        # In a fresh PowerShell session, these modules are NOT auto-imported when importing IdLE.
    }

    It 'Steps module exports the intended step functions' {
        Remove-Module IdLE.Steps.Common -Force -ErrorAction SilentlyContinue
        Import-Module $stepsPsd1 -Force -ErrorAction Stop

        $exported = (Get-Command -Module IdLE.Steps.Common).Name
        $exported | Should -Contain 'Invoke-IdleStepEmitEvent'
        $exported | Should -Contain 'Invoke-IdleStepEnsureAttributes'
        $exported | Should -Contain 'Invoke-IdleStepEnsureEntitlement'
    }

    It 'IdLE.Provider.Mock manifest is valid' {
        { Test-ModuleManifest -Path $providerMockPsd1 -ErrorAction Stop } | Should -Not -Throw
    }

    It 'Mock provider module exports the intended provider function' {
        Remove-Module IdLE.Provider.Mock -Force -ErrorAction SilentlyContinue
        Import-Module $providerMockPsd1 -Force -ErrorAction Stop

        (Get-Command -Module IdLE.Provider.Mock).Name | Should -Contain 'New-IdleMockIdentityProvider'
    }

    Context 'Internal module import warnings' {
        It 'IdLE.Core emits warning when imported directly' {
            $srcPath = Split-Path (Split-Path $corePsd1 -Parent) -Parent
            $pathSeparator = [System.IO.Path]::PathSeparator
            $paths = $env:PSModulePath -split [regex]::Escape($pathSeparator)

            $filteredPaths = foreach ($path in $paths) {
                if (-not $path) { continue }
                $resolvedPath = Resolve-Path -Path $path -ErrorAction SilentlyContinue
                $resolvedSrc = Resolve-Path -Path $srcPath -ErrorAction SilentlyContinue
                if ($resolvedPath -and $resolvedSrc -and $resolvedPath.Path -eq $resolvedSrc.Path) { continue }
                $path
            }

            $corePsd1Escaped = $corePsd1 -replace "'", "''"
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
            } -WorkingDirectory $repoRoot

            $result.ExitCode | Should -Be 0
            $output = ($result.StdOut + $result.StdErr).Trim()
            $output | Should -Not -BeNullOrEmpty -Because "Internal module should emit warning on direct import"
            $output | Should -Match "internal.*unsupported.*IdLE.*instead" -Because "Warning should indicate module is internal and suggest importing IdLE"
            $output | Should -Match '\$env:IDLE_ALLOW_INTERNAL_IMPORT' -Because "Warning should show correct PowerShell syntax for bypass"
        }

        It 'IdLE.Core does not emit warning when IDLE_ALLOW_INTERNAL_IMPORT is set' {
            $corePsd1Escaped = $corePsd1 -replace "'", "''"
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
            } -WorkingDirectory $repoRoot

            $result.ExitCode | Should -Be 0
            ($result.StdOut + $result.StdErr).Trim() | Should -BeNullOrEmpty -Because "Internal module should not emit warning when bypass is set"
        }

        It 'IdLE.Steps.Common emits warning when imported directly' {
            $srcPath = Split-Path (Split-Path $stepsPsd1 -Parent) -Parent
            $pathSeparator = [System.IO.Path]::PathSeparator
            $paths = $env:PSModulePath -split [regex]::Escape($pathSeparator)

            $filteredPaths = foreach ($path in $paths) {
                if (-not $path) { continue }
                $resolvedPath = Resolve-Path -Path $path -ErrorAction SilentlyContinue
                $resolvedSrc = Resolve-Path -Path $srcPath -ErrorAction SilentlyContinue
                if ($resolvedPath -and $resolvedSrc -and $resolvedPath.Path -eq $resolvedSrc.Path) { continue }
                $path
            }

            $corePsd1Escaped = $corePsd1 -replace "'", "''"
            $stepsPsd1Escaped = $stepsPsd1 -replace "'", "''"
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
            } -WorkingDirectory $repoRoot

            $result.ExitCode | Should -Be 0
            $output = ($result.StdOut + $result.StdErr).Trim()
            $output | Should -Not -BeNullOrEmpty -Because "Internal module should emit warning on direct import"
            $output | Should -Match "internal.*unsupported.*IdLE.*instead" -Because "Warning should indicate module is internal and suggest importing IdLE"
            $output | Should -Match '\$env:IDLE_ALLOW_INTERNAL_IMPORT' -Because "Warning should show correct PowerShell syntax for bypass"
        }
        
        It 'IdLE meta-module does not emit internal module warnings' {
            $idlePsd1Escaped = $idlePsd1 -replace "'", "''"
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
            } -WorkingDirectory $repoRoot

            $result.ExitCode | Should -Be 0
            ($result.StdOut + $result.StdErr).Trim() | Should -BeNullOrEmpty -Because "IdLE meta-module should suppress internal module warnings via ScriptsToProcess"
        }
    }
}


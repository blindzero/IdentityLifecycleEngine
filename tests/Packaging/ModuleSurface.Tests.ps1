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
            'New-IdleLifecycleRequest'
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

        $req  = New-IdleLifecycleRequest -LifecycleEvent 'Joiner'

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

    It 'Importing IdLE makes built-in steps available to the engine without exporting them globally' {
        # Remove ALL IdLE modules to ensure clean state (other tests may have imported them)
        Get-Module -All IdLE* | Remove-Module -Force -ErrorAction SilentlyContinue
        
        # Also explicitly remove commands that may have been exported in previous tests
        Remove-Item Function:\Invoke-IdleStepEmitEvent -Force -ErrorAction SilentlyContinue
        Remove-Item Function:\Invoke-IdleStepEnsureAttribute -Force -ErrorAction SilentlyContinue
        Remove-Item Function:\Invoke-IdleStepEnsureEntitlement -Force -ErrorAction SilentlyContinue
        Remove-Item Function:\New-IdlePlanObject -Force -ErrorAction SilentlyContinue
        Remove-Item Function:\Invoke-IdlePlanObject -Force -ErrorAction SilentlyContinue
        
        Import-Module $idlePsd1 -Force -ErrorAction Stop

        # Built-in steps are expected to be available within IdLE (loaded by IdLE.psm1 bootstrap).
        # With name-based import, IdLE.Steps.Common may be visible in global scope if explicitly imported,
        # but when loaded via IdLE bootstrap it should not pollute global session.
        # The key test is that step functions are NOT in global scope.
        (Get-Command -Name Invoke-IdleStepEmitEvent -ErrorAction SilentlyContinue) | Should -BeNullOrEmpty
        (Get-Command -Name Invoke-IdleStepEnsureAttribute -ErrorAction SilentlyContinue) | Should -BeNullOrEmpty
        (Get-Command -Name Invoke-IdleStepEnsureEntitlement -ErrorAction SilentlyContinue) | Should -BeNullOrEmpty

        # Engine discovery must work without global exports (module-qualified handler names).
        InModuleScope IdLE.Core {
            $registry = Get-IdleStepRegistry -Providers $null

            $registry.ContainsKey('IdLE.Step.EmitEvent') | Should -BeTrue
            $registry['IdLE.Step.EmitEvent'] | Should -Be 'IdLE.Steps.Common\Invoke-IdleStepEmitEvent'

            $registry.ContainsKey('IdLE.Step.EnsureAttribute') | Should -BeTrue
            $registry['IdLE.Step.EnsureAttribute'] | Should -Be 'IdLE.Steps.Common\Invoke-IdleStepEnsureAttribute'

            $registry.ContainsKey('IdLE.Step.EnsureEntitlement') | Should -BeTrue
            $registry['IdLE.Step.EnsureEntitlement'] | Should -Be 'IdLE.Steps.Common\Invoke-IdleStepEnsureEntitlement'
        }
    }

    It 'Importing IdLE does not expose IdLE.Core object cmdlets globally' {
        # Remove ALL IdLE modules to ensure clean state (other tests may have imported them)
        Get-Module -All IdLE* | Remove-Module -Force -ErrorAction SilentlyContinue
        
        # Also explicitly remove commands that may have been exported in previous tests
        Remove-Item Function:\New-IdlePlanObject -Force -ErrorAction SilentlyContinue
        Remove-Item Function:\Invoke-IdlePlanObject -Force -ErrorAction SilentlyContinue
        Remove-Item Function:\Invoke-IdleStepEmitEvent -Force -ErrorAction SilentlyContinue
        Remove-Item Function:\Invoke-IdleStepEnsureAttribute -Force -ErrorAction SilentlyContinue
        
        Import-Module $idlePsd1 -Force -ErrorAction Stop

        # IdLE.Core object cmdlets should not be in global scope
        (Get-Command New-IdlePlanObject -ErrorAction SilentlyContinue) | Should -BeNullOrEmpty
        (Get-Command Invoke-IdlePlanObject -ErrorAction SilentlyContinue) | Should -BeNullOrEmpty
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
        
        Import-Module $idlePsd1 -Force -ErrorAction Stop

        $idle = Get-Module IdLE
        $idle | Should -Not -BeNullOrEmpty

        # Define expected baseline modules in one place
        $baselineModules = @('IdLE.Core', 'IdLE.Steps.Common')

        # With name-based import, baseline modules are loaded by IdLE.psm1 bootstrap
        # Verify public API is available (depends on Core and Steps.Common being loaded)
        $publicCommands = (Get-Command -Module IdLE).Name
        $publicCommands | Should -Contain 'New-IdlePlan'
        $publicCommands | Should -Contain 'Invoke-IdlePlan'
        
        # Verify built-in steps are available (depends on Steps.Common)
        InModuleScope IdLE.Core {
            $registry = Get-IdleStepRegistry -Providers $null
            $registry.ContainsKey('IdLE.Step.EmitEvent') | Should -BeTrue
        }

        # Verify no optional providers or step modules are imported globally  
        # Optional modules should only be imported when explicitly requested
        # Use Get-Module -All to catch modules imported in any scope
        $optionalProviders = @('IdLE.Provider.AD', 'IdLE.Provider.EntraID', 'IdLE.Provider.ExchangeOnline', 'IdLE.Provider.DirectorySync.EntraConnect')
        $optionalSteps = @('IdLE.Steps.DirectorySync', 'IdLE.Steps.Mailbox')
        
        foreach ($moduleName in ($optionalProviders + $optionalSteps)) {
            (Get-Module -All -Name $moduleName) | Should -BeNullOrEmpty -Because "$moduleName should not be auto-imported"
        }
    }

    It 'Steps module exports the intended step functions' {
        Remove-Module IdLE.Steps.Common -Force -ErrorAction SilentlyContinue
        Import-Module $stepsPsd1 -Force -ErrorAction Stop

        $exported = (Get-Command -Module IdLE.Steps.Common).Name
        $exported | Should -Contain 'Invoke-IdleStepEmitEvent'
        $exported | Should -Contain 'Invoke-IdleStepEnsureAttribute'
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
            $existingModule = Get-Module -Name IdLE.Core
            if ($existingModule) {
                Set-ItResult -Skipped -Because "IdLE.Core is already loaded; cannot test direct import warning"
                return
            }
            
            $originalValue = $env:IDLE_ALLOW_INTERNAL_IMPORT
            try {
                $env:IDLE_ALLOW_INTERNAL_IMPORT = $null
                
                # Import and capture warning output
                $output = Import-Module $corePsd1 -Force 3>&1 | Out-String
                
                $output | Should -Not -BeNullOrEmpty -Because "Internal module should emit warning on direct import"
                $output | Should -Match "internal.*unsupported.*IdLE.*instead" -Because "Warning should indicate module is internal and suggest importing IdLE"
                $output | Should -Match '\$env:IDLE_ALLOW_INTERNAL_IMPORT' -Because "Warning should show correct PowerShell syntax for bypass"
            }
            finally {
                $env:IDLE_ALLOW_INTERNAL_IMPORT = $originalValue
                Remove-Module IdLE.Core -Force -ErrorAction SilentlyContinue
            }
        }

        It 'IdLE.Core does not emit warning when IDLE_ALLOW_INTERNAL_IMPORT is set' {
            $existingModule = Get-Module -Name IdLE.Core
            if ($existingModule) {
                Set-ItResult -Skipped -Because "IdLE.Core is already loaded; cannot test bypass"
                return
            }
            
            $originalValue = $env:IDLE_ALLOW_INTERNAL_IMPORT
            try {
                $env:IDLE_ALLOW_INTERNAL_IMPORT = '1'
                
                # Import and capture warning output
                $output = Import-Module $corePsd1 -Force 3>&1 | Out-String
                
                $output | Should -BeNullOrEmpty -Because "Internal module should not emit warning when bypass is set"
            }
            finally {
                $env:IDLE_ALLOW_INTERNAL_IMPORT = $originalValue
                Remove-Module IdLE.Core -Force -ErrorAction SilentlyContinue
            }
        }

        It 'IdLE.Steps.Common emits warning when imported directly' {
            $existingModule = Get-Module -Name IdLE.Steps.Common
            if ($existingModule) {
                Set-ItResult -Skipped -Because "IdLE.Steps.Common is already loaded; cannot test direct import warning"
                return
            }
            
            $originalValue = $env:IDLE_ALLOW_INTERNAL_IMPORT
            try {
                $env:IDLE_ALLOW_INTERNAL_IMPORT = $null
                
                # Import and capture warning output
                $output = Import-Module $stepsPsd1 -Force 3>&1 | Out-String
                
                $output | Should -Not -BeNullOrEmpty -Because "Internal module should emit warning on direct import"
                $output | Should -Match "internal.*unsupported.*IdLE.*instead" -Because "Warning should indicate module is internal and suggest importing IdLE"
                $output | Should -Match '\$env:IDLE_ALLOW_INTERNAL_IMPORT' -Because "Warning should show correct PowerShell syntax for bypass"
            }
            finally {
                $env:IDLE_ALLOW_INTERNAL_IMPORT = $originalValue
                Remove-Module IdLE.Steps.Common -Force -ErrorAction SilentlyContinue
            }
        }
        
        It 'IdLE meta-module does not emit internal module warnings' {
            $originalValue = $env:IDLE_ALLOW_INTERNAL_IMPORT
            try {
                $env:IDLE_ALLOW_INTERNAL_IMPORT = $null
                
                # Import and capture warning output
                $output = Import-Module $idlePsd1 -Force 3>&1 | Out-String
                
                $output | Should -BeNullOrEmpty -Because "IdLE meta-module should suppress internal module warnings via ScriptsToProcess"
            }
            finally {
                $env:IDLE_ALLOW_INTERNAL_IMPORT = $originalValue
                Remove-Module IdLE -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

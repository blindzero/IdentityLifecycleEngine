BeforeAll {
    $repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
    $idlePsd1 = Join-Path $repoRoot 'src\IdLE\IdLE.psd1'
    $corePsd1 = Join-Path $repoRoot 'src\IdLE.Core\IdLE.Core.psd1'
    $stepsPsd1 = Join-Path $repoRoot 'src\IdLE.Steps.Common\IdLE.Steps.Common.psd1'
    $providerMockPsd1 = Join-Path $repoRoot 'src\IdLE.Provider.Mock\IdLE.Provider.Mock.psd1'

    . (Join-Path $PSScriptRoot '_testHelpers.ps1')
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
        Remove-Module IdLE, IdLE.Core, IdLE.Steps.Common -Force -ErrorAction SilentlyContinue
        Import-Module $idlePsd1 -Force -ErrorAction Stop

        # Built-in steps are expected to be available within IdLE (nested/hidden module is ok).
        (Get-Module -All IdLE.Steps.Common) | Should -Not -BeNullOrEmpty

        # But they must not pollute the global session state:
        (Get-Module -Name IdLE.Steps.Common) | Should -BeNullOrEmpty
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
        Remove-Module IdLE, IdLE.Core -Force -ErrorAction SilentlyContinue
        Import-Module $idlePsd1 -Force -ErrorAction Stop

        (Get-Command New-IdlePlanObject -ErrorAction SilentlyContinue) | Should -BeNullOrEmpty
        (Get-Command Invoke-IdlePlanObject -ErrorAction SilentlyContinue) | Should -BeNullOrEmpty
    }

    It 'IdLE module includes IdLE.Core and IdLE.Steps.Common as nested modules' {
        Remove-Module IdLE -Force -ErrorAction SilentlyContinue
        Import-Module $idlePsd1 -Force -ErrorAction Stop

        $idle = Get-Module IdLE
        $idle | Should -Not -BeNullOrEmpty

        ($idle.NestedModules | Where-Object Name -eq 'IdLE.Core') | Should -Not -BeNullOrEmpty
        ($idle.NestedModules | Where-Object Name -eq 'IdLE.Steps.Common') | Should -Not -BeNullOrEmpty
    }

    It 'IdLE auto-imports only baseline modules (Core and Steps.Common), not optional modules' {
        # Clean test state - remove baseline modules to ensure fresh import
        # We don't remove optional modules to maintain test isolation (other tests may have them loaded)
        Remove-Module IdLE, IdLE.Core, IdLE.Steps.Common -Force -ErrorAction SilentlyContinue
        Import-Module $idlePsd1 -Force -ErrorAction Stop

        $idle = Get-Module IdLE
        $idle | Should -Not -BeNullOrEmpty

        # Define expected baseline modules in one place
        $baselineModules = @('IdLE.Core', 'IdLE.Steps.Common')

        # Baseline modules should be auto-imported (explicit positive check)
        foreach ($moduleName in $baselineModules) {
            ($idle.NestedModules | Where-Object Name -eq $moduleName) | Should -Not -BeNullOrEmpty -Because "$moduleName should be auto-imported"
        }

        # Only baseline modules should be nested (count check ensures no extras)
        @($idle.NestedModules).Count | Should -Be $baselineModules.Count

        # Verify no optional modules are nested (generalized negative check using pattern)
        # This pattern matches: IdLE.Provider.* or IdLE.Steps.* (except Steps.Common)
        $nestedNames = @($idle.NestedModules | Select-Object -ExpandProperty Name)
        $optionalModulePattern = '^IdLE\.(Provider\.|Steps\.(?!Common$))'
        $unexpectedModules = $nestedNames | Where-Object { $_ -match $optionalModulePattern }
        $unexpectedModules | Should -BeNullOrEmpty -Because "Optional modules should not be auto-imported"
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
        It 'IdLE.Core emits warning when imported directly without bypass' {
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

        It 'IdLE.Steps.Common emits warning when imported directly without bypass' {
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
            }
            finally {
                $env:IDLE_ALLOW_INTERNAL_IMPORT = $originalValue
                Remove-Module IdLE.Steps.Common -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

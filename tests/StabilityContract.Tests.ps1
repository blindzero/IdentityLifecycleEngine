Set-StrictMode -Version Latest

BeforeAll {
    . (Join-Path $PSScriptRoot '_testHelpers.ps1')
    Import-IdleTestModule
}

Describe 'IdLE v1.0 Stability Contract' {
    Context 'Supported public API surface' {
        It 'IdLE exports exactly the v1.0 supported command set' {
            # Source of truth: src/IdLE/IdLE.psd1 FunctionsToExport
            # This is the minimal supported surface for v1.0.0
            $expectedCommands = @(
                'Test-IdleWorkflow'
                'New-IdleLifecycleRequest'
                'New-IdlePlan'
                'Invoke-IdlePlan'
                'Export-IdlePlan'
                'New-IdleAuthSessionBroker'
            ) | Sort-Object

            $actualCommands = (Get-Command -Module IdLE -CommandType Function).Name | Sort-Object

            # Exact match: no more, no less
            $actualCommands | Should -Be $expectedCommands -Because "IdLE v1.0 must export exactly the documented supported commands"
        }

        It 'IdLE does not export cmdlets or aliases' {
            $cmdlets = Get-Command -Module IdLE -CommandType Cmdlet -ErrorAction SilentlyContinue
            $cmdlets | Should -BeNullOrEmpty -Because "IdLE should only export functions, not cmdlets"

            $aliases = Get-Command -Module IdLE -CommandType Alias -ErrorAction SilentlyContinue
            $aliases | Should -BeNullOrEmpty -Because "IdLE v1.0 does not export aliases"
        }
    }

    Context 'Internal modules emit warnings when imported directly' {
        It 'IdLE.Core emits warning when imported directly without bypass' {
            # Skip this test if running as part of the overall test suite where IdLE.Core is already loaded
            $existingModule = Get-Module -Name IdLE.Core
            if ($existingModule) {
                Set-ItResult -Skipped -Because "IdLE.Core is already loaded; cannot test direct import warning"
                return
            }

            $corePsd1 = Join-Path $PSScriptRoot '..' 'src' 'IdLE.Core' 'IdLE.Core.psd1'
            
            # Clear the bypass env var
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

            $corePsd1 = Join-Path $PSScriptRoot '..' 'src' 'IdLE.Core' 'IdLE.Core.psd1'
            
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

            $stepsPsd1 = Join-Path $PSScriptRoot '..' 'src' 'IdLE.Steps.Common' 'IdLE.Steps.Common.psd1'
            
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

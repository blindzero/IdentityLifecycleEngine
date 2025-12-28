BeforeAll {
    $repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
    $idlePsd1 = Join-Path $repoRoot 'src\IdLE\IdLE.psd1'
    $corePsd1 = Join-Path $repoRoot 'src\IdLE.Core\IdLE.Core.psd1'
    $stepsPsd1 = Join-Path $repoRoot 'src\IdLE.Steps.Common\IdLE.Steps.Common.psd1'
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
            'New-IdleLifecycleRequest'
            'New-IdlePlan'
            'Test-IdleWorkflow'
        ) | Sort-Object

        $actual = (Get-Command -Module IdLE).Name | Sort-Object

        $actual | Should -Be $expected
    }

    It 'Importing IdLE does not load IdLE.Steps.Common by default' {
        Remove-Module IdLE, IdLE.Steps.Common -Force -ErrorAction SilentlyContinue
        Import-Module $idlePsd1 -Force -ErrorAction Stop

        (Get-Module IdLE.Steps.Common) | Should -BeNullOrEmpty
        (Get-Command Invoke-IdleStepEmitEvent -ErrorAction SilentlyContinue) | Should -BeNullOrEmpty
    }

    It 'Importing IdLE does not expose IdLE.Core object cmdlets globally' {
        Remove-Module IdLE, IdLE.Core -Force -ErrorAction SilentlyContinue
        Import-Module $idlePsd1 -Force -ErrorAction Stop

        (Get-Command New-IdlePlanObject -ErrorAction SilentlyContinue) | Should -BeNullOrEmpty
        (Get-Command Invoke-IdlePlanObject -ErrorAction SilentlyContinue) | Should -BeNullOrEmpty
    }

    It 'IdLE module includes IdLE.Core as nested module' {
        Remove-Module IdLE -Force -ErrorAction SilentlyContinue
        Import-Module $idlePsd1 -Force -ErrorAction Stop

        $idle = Get-Module IdLE
        $idle | Should -Not -BeNullOrEmpty

        ($idle.NestedModules | Where-Object Name -eq 'IdLE.Core') | Should -Not -BeNullOrEmpty
    }

    It 'Steps module exports the intended step function' {
        Remove-Module IdLE.Steps.Common -Force -ErrorAction SilentlyContinue
        Import-Module $stepsPsd1 -Force -ErrorAction Stop

        (Get-Command -Module IdLE.Steps.Common).Name | Should -Contain 'Invoke-IdleStepEmitEvent'
    }
}

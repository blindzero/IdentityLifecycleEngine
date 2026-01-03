Set-StrictMode -Version Latest

Describe 'IdLE.Provider.Mock - Mock identity provider' {

    BeforeAll {
        # Use a relative import from the current working directory (repo root) used by the test runner.
        # This keeps the test simple and avoids repo-root discovery issues in Pester discovery/runtime.
        $modulePath = Join-Path -Path (Get-Location).Path -ChildPath 'src\IdLE.Provider.Mock\IdLE.Provider.Mock.psd1'
        if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf)) {
            throw "Provider module manifest not found at: $modulePath"
        }

        Import-Module -Name $modulePath -Force -ErrorAction Stop

        # Load provider contract helpers (no Describe/It at top-level; safe for Pester discovery).
        $identityContractPath = Join-Path -Path (Get-Location).Path -ChildPath 'tests\ProviderContracts\IdentityProvider.Contract.ps1'
        if (-not (Test-Path -LiteralPath $identityContractPath -PathType Leaf)) {
            throw "Identity provider contract not found at: $identityContractPath"
        }
        . $identityContractPath

        $capabilitiesContractPath = Join-Path -Path (Get-Location).Path -ChildPath 'tests\ProviderContracts\ProviderCapabilities.Contract.ps1'
        if (-not (Test-Path -LiteralPath $capabilitiesContractPath -PathType Leaf)) {
            throw "Provider capabilities contract not found at: $capabilitiesContractPath"
        }
        . $capabilitiesContractPath
    }

    It 'Creates a provider instance' {
        $provider = New-IdleMockIdentityProvider

        $provider | Should -Not -BeNullOrEmpty
        $provider.Name | Should -Be 'MockIdentityProvider'
    }

    Context 'Provider contracts' {

        Invoke-IdleIdentityProviderContractTests -NewProvider {
            New-IdleMockIdentityProvider
        } -ProviderLabel 'Mock identity provider'

        Invoke-IdleProviderCapabilitiesContractTests -ProviderFactory {
            New-IdleMockIdentityProvider
        }
    }

    It 'Keeps state scoped to the provider instance' {
        $p1 = New-IdleMockIdentityProvider
        $p2 = New-IdleMockIdentityProvider

        $null = $p1.EnsureAttribute('user1', 'Department', 'IT')

        $i1 = $p1.GetIdentity('user1')
        $i2 = $p2.GetIdentity('user1')

        $i1.Attributes['Department'] | Should -Be 'IT'
        $i2.Attributes.ContainsKey('Department') | Should -BeFalse
    }

    It 'Supports pre-seeded identities via InitialStore' {
        $provider = New-IdleMockIdentityProvider -InitialStore @{
            'user1' = @{
                IdentityKey = 'user1'
                Enabled     = $true
                Attributes  = @{ Department = 'HR' }
            }
        }

        $identity = $provider.GetIdentity('user1')
        $identity.Attributes['Department'] | Should -Be 'HR'

        $r = $provider.EnsureAttribute('user1', 'Department', 'HR')
        $r.Changed | Should -BeFalse
    }
}

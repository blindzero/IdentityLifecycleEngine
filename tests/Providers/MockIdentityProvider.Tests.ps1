Set-StrictMode -Version Latest

BeforeDiscovery {
    . (Join-Path -Path $PSScriptRoot -ChildPath '..\_testHelpers.ps1')
    Import-IdleTestModule

    # $PSScriptRoot = ...\tests\Providers
    # repo root     = parent of ...\tests
    $testsRoot = Split-Path -Path $PSScriptRoot -Parent
    $repoRoot  = Split-Path -Path $testsRoot -Parent

    $identityContractPath = Join-Path -Path $repoRoot -ChildPath 'tests\ProviderContracts\IdentityProvider.Contract.ps1'
    if (-not (Test-Path -LiteralPath $identityContractPath -PathType Leaf)) {
        throw "Identity provider contract not found at: $identityContractPath"
    }
    . $identityContractPath

    $capabilitiesContractPath = Join-Path -Path $repoRoot -ChildPath 'tests\ProviderContracts\ProviderCapabilities.Contract.ps1'
    if (-not (Test-Path -LiteralPath $capabilitiesContractPath -PathType Leaf)) {
        throw "Provider capabilities contract not found at: $capabilitiesContractPath"
    }
    . $capabilitiesContractPath

    $entitlementContractPath = Join-Path -Path $repoRoot -ChildPath 'tests\ProviderContracts\EntitlementProvider.Contract.ps1'
    if (-not (Test-Path -LiteralPath $entitlementContractPath -PathType Leaf)) {
        throw "Entitlement provider contract not found at: $entitlementContractPath"
    }
    . $entitlementContractPath
}

Describe 'Mock identity provider' {
    Context 'Contracts' {
        Invoke-IdleIdentityProviderContractTests -NewProvider { New-IdleMockIdentityProvider }
        Invoke-IdleProviderCapabilitiesContractTests -ProviderFactory { New-IdleMockIdentityProvider }
        Invoke-IdleEntitlementProviderContractTests -NewProvider { New-IdleMockIdentityProvider }
    }

    Context 'Capabilities' {
        It 'Advertises IdLE.Entitlement.Prune capability' {
            $provider = New-IdleMockIdentityProvider

            $caps = $provider.GetCapabilities()
            $caps | Should -Contain 'IdLE.Entitlement.Prune'
        }

        It 'Advertises all expected entitlement capabilities' {
            $provider = New-IdleMockIdentityProvider

            $caps = $provider.GetCapabilities()
            $caps | Should -Contain 'IdLE.Entitlement.List'
            $caps | Should -Contain 'IdLE.Entitlement.Grant'
            $caps | Should -Contain 'IdLE.Entitlement.Revoke'
            $caps | Should -Contain 'IdLE.Entitlement.Prune'
        }
    }
}

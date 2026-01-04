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

Describe 'Mock identity provider contracts' {
    Invoke-IdleIdentityProviderContractTests -NewProvider { New-IdleMockIdentityProvider }
    Invoke-IdleProviderCapabilitiesContractTests -ProviderFactory { New-IdleMockIdentityProvider }
    Invoke-IdleEntitlementProviderContractTests -NewProvider { New-IdleMockIdentityProvider }
}

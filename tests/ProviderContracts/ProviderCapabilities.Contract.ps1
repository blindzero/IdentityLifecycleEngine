Set-StrictMode -Version Latest

function Invoke-IdleProviderCapabilitiesContractTests {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [scriptblock] $ProviderFactory,

        [Parameter()]
        [switch] $AllowEmpty
    )

    $cases = @(
        @{
            ProviderFactory = $ProviderFactory
            AllowEmpty      = [bool]$AllowEmpty
        }
    )

    Context 'Capability advertisement' -ForEach $cases {
        BeforeAll {
            $providerFactory = $_.ProviderFactory

            if ($null -eq $providerFactory) {
                throw 'ProviderFactory scriptblock is required for capability contract tests.'
            }

            $provider = & $providerFactory
            if ($null -eq $provider) {
                throw 'ProviderFactory returned $null. A provider instance is required for contract tests.'
            }

            $script:Provider = $provider
            $script:AllowEmpty = $_.AllowEmpty
        }

        It 'Exposes GetCapabilities as a method' {
            $script:Provider.PSObject.Methods.Name | Should -Contain 'GetCapabilities'
        }

        It 'GetCapabilities returns a string list' {
            $caps = $script:Provider.GetCapabilities()

            $caps | Should -Not -BeNullOrEmpty
            foreach ($c in $caps) {
                $c | Should -BeOfType [string]
                $c | Should -Not -BeNullOrEmpty
            }
        }

        It 'GetCapabilities returns stable identifiers (no whitespace)' {
            $caps = $script:Provider.GetCapabilities()

            foreach ($c in $caps) {
                $c | Should -Not -Match '\s'
            }
        }

        It 'GetCapabilities can be empty only when explicitly allowed' {
            $caps = $script:Provider.GetCapabilities()

            if (-not $script:AllowEmpty) {
                $caps.Count | Should -BeGreaterThan 0
            }
        }
    }
}

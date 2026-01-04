Set-StrictMode -Version Latest

function Invoke-IdleProviderCapabilitiesContractTests {
    <#
    .SYNOPSIS
    Defines provider contract tests for capability advertisement.

    .DESCRIPTION
    This file intentionally contains no top-level Describe/It blocks.
    It provides a function that must be invoked from within a Describe block.

    IMPORTANT (Pester 5):
    - The contract must be registered during discovery (Describe/Context scope).
    - The provider instance must be created during runtime (BeforeAll), not during discovery.

    Providers must advertise capabilities via a ScriptMethod named 'GetCapabilities'
    which returns a list of stable capability identifiers (strings).

    .PARAMETER ProviderFactory
    ScriptBlock that creates and returns a provider instance.

    .PARAMETER AllowEmpty
    When set, the provider may return an empty capability list (rare; generally discouraged).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [scriptblock] $ProviderFactory,

        [Parameter()]
        [switch] $AllowEmpty
    )

    Context 'Capability advertisement' -ForEach @(@{ ProviderFactory = $ProviderFactory }) {
        param($ctx)

        BeforeAll {
            $providerFactory = $ctx.ProviderFactory

            if ($null -eq $providerFactory) {
                throw 'ProviderFactory scriptblock is required for capability contract tests.'
            }

            if ($providerFactory -isnot [scriptblock]) {
                throw 'ProviderFactory must be a scriptblock that returns a provider instance.'
            }

            $script:Provider = & ($providerFactory.GetNewClosure())
            if ($null -eq $script:Provider) {
                throw 'ProviderFactory returned $null. A provider instance is required for contract tests.'
            }
        }

        It 'Exposes GetCapabilities as a method' {
            $script:Provider.PSObject.Methods.Name | Should -Contain 'GetCapabilities'
        }

        It 'GetCapabilities returns stable capability identifiers' {
            $c1 = @(& $script:Provider.GetCapabilities())
            $c2 = @(& $script:Provider.GetCapabilities())

            if (-not $AllowEmpty) {
                $c1.Count | Should -BeGreaterThan 0
            }

            foreach ($c in $c1) {
                $c | Should -BeOfType [string]
                $c.Trim() | Should -Not -BeNullOrEmpty

                # Capability naming convention:
                # - dot-separated segments
                # - no whitespace
                # - starts with a letter
                # Example: 'Identity.Read', 'Entitlement.Write'
                $c | Should -Match '^[A-Za-z][A-Za-z0-9]*(\.[A-Za-z0-9]+)+$'
            }

            # No duplicates (providers should not over-advertise or double-advertise).
            (@($c1 | Sort-Object -Unique)).Count | Should -Be $c1.Count

            # Deterministic set (order-insensitive).
            @($c1 | Sort-Object) | Should -Be @($c2 | Sort-Object)
        }
    }
}

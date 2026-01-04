Set-StrictMode -Version Latest

function Invoke-IdleIdentityProviderContractTests {
    <#
    .SYNOPSIS
    Defines provider contract tests for an identity provider implementation.

    .DESCRIPTION
    This file intentionally contains no top-level Describe/It blocks.
    It provides a function that must be invoked from within a Describe block.

    IMPORTANT (Pester 5):
    - The contract must be registered during discovery (Describe/Context scope).
    - The provider instance must be created during runtime (BeforeAll), not during discovery.

    Therefore the contract takes a provider factory scriptblock and creates the provider
    inside its own BeforeAll.

    .PARAMETER NewProvider
    ScriptBlock that creates a new provider instance.

    .PARAMETER ProviderLabel
    Optional label for better test output.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [scriptblock] $NewProvider,

        [Parameter()]
        [string] $ProviderLabel = 'Identity provider'
    )

    Context "$ProviderLabel contract" -ForEach @(@{ ProviderFactory = $NewProvider }) {
        param($ctx)

        BeforeAll {
            $providerFactory = $ctx.ProviderFactory

            if ($null -eq $providerFactory) {
                throw 'NewProvider scriptblock is required for identity provider contract tests.'
            }

            if ($providerFactory -isnot [scriptblock]) {
                throw 'NewProvider must be a scriptblock that returns a provider instance.'
            }

            $script:Provider = & ($providerFactory.GetNewClosure())
            if ($null -eq $script:Provider) {
                throw 'NewProvider returned $null. A provider instance is required for contract tests.'
            }
        }

        It 'Exposes required methods' {
            $script:Provider.PSObject.Methods.Name | Should -Contain 'GetIdentity'
            $script:Provider.PSObject.Methods.Name | Should -Contain 'EnsureAttribute'
            $script:Provider.PSObject.Methods.Name | Should -Contain 'DisableIdentity'
        }

        It 'GetIdentity returns a hashtable with required keys' {
            $id = "contract-$([guid]::NewGuid().ToString('N'))"
            $identity = $script:Provider.GetIdentity($id)

            $identity | Should -BeOfType [hashtable]
            $identity.Keys | Should -Contain 'IdentityKey'
            $identity.Keys | Should -Contain 'Enabled'
            $identity.Keys | Should -Contain 'Attributes'

            $identity.IdentityKey | Should -Be $id
            $identity.Attributes | Should -BeOfType [hashtable]
        }

        It 'EnsureAttribute is idempotent and returns a Changed flag' {
            $id = "contract-$([guid]::NewGuid().ToString('N'))"

            $r1 = $script:Provider.EnsureAttribute($id, 'Department', 'IT')
            $r2 = $script:Provider.EnsureAttribute($id, 'Department', 'IT')

            $r1.PSObject.Properties.Name | Should -Contain 'Changed'
            $r1.Changed | Should -BeTrue

            $r2.PSObject.Properties.Name | Should -Contain 'Changed'
            $r2.Changed | Should -BeFalse
        }

        It 'DisableIdentity is idempotent and returns a Changed flag' {
            $id = "contract-$([guid]::NewGuid().ToString('N'))"

            $r1 = $script:Provider.DisableIdentity($id)
            $r2 = $script:Provider.DisableIdentity($id)

            $r1.PSObject.Properties.Name | Should -Contain 'Changed'
            $r1.Changed | Should -BeTrue

            $r2.PSObject.Properties.Name | Should -Contain 'Changed'
            $r2.Changed | Should -BeFalse
        }
    }
}

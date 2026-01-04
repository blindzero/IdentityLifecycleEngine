Set-StrictMode -Version Latest

function Invoke-IdleEntitlementProviderContractTests {
    <#
    .SYNOPSIS
    Defines provider contract tests for entitlement operations.

    .DESCRIPTION
    This file intentionally contains no top-level Describe/It blocks.
    It provides a function that must be invoked from within a Describe block.

    IMPORTANT (Pester 5):
    - The contract must be registered during discovery (Describe/Context scope).
    - The provider instance must be created during runtime (BeforeAll), not during discovery.

    Providers must expose entitlement operations for identities:
    - ListEntitlements(identityKey)
    - GrantEntitlement(identityKey, entitlement)
    - RevokeEntitlement(identityKey, entitlement)

    Providers must also advertise the following capabilities via GetCapabilities():
    - IdLE.Entitlement.List
    - IdLE.Entitlement.Grant
    - IdLE.Entitlement.Revoke

    .PARAMETER NewProvider
    ScriptBlock that creates and returns a provider instance.

    .PARAMETER ProviderLabel
    Optional label for better test output.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [scriptblock] $NewProvider,

        [Parameter()]
        [string] $ProviderLabel = 'Entitlement provider'
    )

    Context "$ProviderLabel contract" {

        BeforeAll {
            $script:Provider = & $NewProvider
            if ($null -eq $script:Provider) {
                throw 'Provider factory returned $null.'
            }
        }

        It 'Exposes required entitlement methods and capabilities' {
            $methods = @($script:Provider.PSObject.Methods.Name)
            $methods | Should -Contain 'ListEntitlements'
            $methods | Should -Contain 'GrantEntitlement'
            $methods | Should -Contain 'RevokeEntitlement'

            $capabilities = @($script:Provider.GetCapabilities())
            $capabilities | Should -Contain 'IdLE.Entitlement.List'
            $capabilities | Should -Contain 'IdLE.Entitlement.Grant'
            $capabilities | Should -Contain 'IdLE.Entitlement.Revoke'
        }

        It 'ListEntitlements fails for a non-existent identity' {
            { $script:Provider.ListEntitlements('missing-identity') } | Should -Throw
        }

        It 'GrantEntitlement is idempotent' {
            $id = "contract-$([guid]::NewGuid().ToString('N'))"
            $entitlement = @{ Kind = 'Group'; Id = 'id-123'; DisplayName = 'Group 123' }

            # Create the identity in a provider-agnostic way.
            if ($script:Provider.PSObject.Methods.Name -contains 'EnsureAttribute') {
                $null = $script:Provider.EnsureAttribute($id, 'Seed', 'Value')
            }

            $r1 = $script:Provider.GrantEntitlement($id, $entitlement)
            $r1.PSObject.Properties.Name | Should -Contain 'Changed'
            $r1.Changed | Should -BeTrue

            $r2 = $script:Provider.GrantEntitlement($id, @{ Kind = 'Group'; Id = 'ID-123' })
            $r2.PSObject.Properties.Name | Should -Contain 'Changed'
            $r2.Changed | Should -BeFalse

            $assignments = @($script:Provider.ListEntitlements($id))
            $assignments | Where-Object { $_.Kind -eq 'Group' -and $_.Id -eq 'id-123' } | Should -Not -BeNullOrEmpty
        }

        It 'RevokeEntitlement is idempotent' {
            $id = "contract-$([guid]::NewGuid().ToString('N'))"
            $entitlement = @{ Kind = 'License'; Id = 'sku-basic'; DisplayName = 'Basic SKU' }

            if ($script:Provider.PSObject.Methods.Name -contains 'EnsureAttribute') {
                $null = $script:Provider.EnsureAttribute($id, 'Seed', 'Value')
            }

            $null = $script:Provider.GrantEntitlement($id, $entitlement)

            $r1 = $script:Provider.RevokeEntitlement($id, $entitlement)
            $r1.PSObject.Properties.Name | Should -Contain 'Changed'
            $r1.Changed | Should -BeTrue

            $r2 = $script:Provider.RevokeEntitlement($id, $entitlement)
            $r2.PSObject.Properties.Name | Should -Contain 'Changed'
            $r2.Changed | Should -BeFalse

            $assignments = @($script:Provider.ListEntitlements($id))
            $assignments | Where-Object { $_.Kind -eq 'License' -and $_.Id -eq 'sku-basic' } | Should -BeNullOrEmpty
        }
    }
}

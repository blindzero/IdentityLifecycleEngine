Set-StrictMode -Version Latest

function Invoke-IdleEntitlementProviderContractTests {
    <#
    .SYNOPSIS
    Defines provider contract tests for an entitlement provider implementation.

    .DESCRIPTION
    This file intentionally contains no top-level Describe/It blocks.
    It provides a function that must be invoked from within a Describe block.

    IMPORTANT (Pester 5):
    - The contract must be registered during discovery (Describe/Context scope).
    - The provider instance must be created during runtime (BeforeAll), not during discovery.

    This contract expects the following methods on the provider:
    - ListEntitlements(IdentityKey)
    - GrantEntitlement(IdentityKey, Entitlement)
    - RevokeEntitlement(IdentityKey, Entitlement)

    Entitlement is treated as a value object with at least:
    - Kind (string)
    - Id (string)
    - DisplayName (optional)

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

    # Capture inside closure for run phase (Pester 5 discovery vs run).
    $providerFactory = $NewProvider.GetNewClosure()

    Context "$ProviderLabel contract" {
        BeforeAll {
            if ($null -eq $providerFactory) {
                throw 'NewProvider scriptblock is required for entitlement provider contract tests.'
            }

            if ($providerFactory -isnot [scriptblock]) {
                throw 'NewProvider must be a scriptblock that returns a provider instance.'
            }

            $script:Provider = & $providerFactory
            if ($null -eq $script:Provider) {
                throw 'NewProvider returned $null. A provider instance is required for contract tests.'
            }
        }

        It 'Exposes required methods' {
            $script:Provider.PSObject.Methods.Name | Should -Contain 'ListEntitlements'
            $script:Provider.PSObject.Methods.Name | Should -Contain 'GrantEntitlement'
            $script:Provider.PSObject.Methods.Name | Should -Contain 'RevokeEntitlement'
        }

        It 'GrantEntitlement returns a stable result shape' {
            $id = "contract-$([guid]::NewGuid().ToString('N'))"

            # Ensure identity exists (some providers are strict).
            [void]$script:Provider.GetIdentity($id)

            $entitlement = [pscustomobject]@{
                Kind        = 'Contract'
                Id          = "entitlement-$([guid]::NewGuid().ToString('N'))"
                DisplayName = 'Contract Entitlement'
            }

            $result = $script:Provider.GrantEntitlement($id, $entitlement)

            $result | Should -Not -BeNullOrEmpty
            $result.PSObject.Properties.Name | Should -Contain 'Changed'
            $result.PSObject.Properties.Name | Should -Contain 'IdentityKey'
            $result.PSObject.Properties.Name | Should -Contain 'Entitlement'

            $result.IdentityKey | Should -Be $id
            $result.Changed | Should -BeOfType [bool]

            $result.Entitlement | Should -Not -BeNullOrEmpty
            $result.Entitlement.PSObject.Properties.Name | Should -Contain 'Kind'
            $result.Entitlement.PSObject.Properties.Name | Should -Contain 'Id'
        }

        It 'GrantEntitlement is idempotent' {
            $id = "contract-$([guid]::NewGuid().ToString('N'))"

            [void]$script:Provider.GetIdentity($id)

            $entitlement = [pscustomobject]@{
                Kind = 'Contract'
                Id   = "entitlement-$([guid]::NewGuid().ToString('N'))"
            }

            $r1 = $script:Provider.GrantEntitlement($id, $entitlement)
            $r2 = $script:Provider.GrantEntitlement($id, $entitlement)

            $r1.Changed | Should -BeTrue
            $r2.Changed | Should -BeFalse
        }

        It 'RevokeEntitlement is idempotent (after a grant)' {
            $id = "contract-$([guid]::NewGuid().ToString('N'))"

            [void]$script:Provider.GetIdentity($id)

            $entitlement = [pscustomobject]@{
                Kind = 'Contract'
                Id   = "entitlement-$([guid]::NewGuid().ToString('N'))"
            }

            [void]$script:Provider.GrantEntitlement($id, $entitlement)

            $r1 = $script:Provider.RevokeEntitlement($id, $entitlement)
            $r2 = $script:Provider.RevokeEntitlement($id, $entitlement)

            $r1.Changed | Should -BeTrue
            $r2.Changed | Should -BeFalse
        }

        It 'ListEntitlements reflects grant and revoke operations' {
            $id = "contract-$([guid]::NewGuid().ToString('N'))"

            [void]$script:Provider.GetIdentity($id)

            $entitlement = [pscustomobject]@{
                Kind = 'Contract'
                Id   = "entitlement-$([guid]::NewGuid().ToString('N'))"
            }

            # Normalize ListEntitlements results:
            # Providers may return $null to indicate "no entitlements". Treat that as empty.
            $before = @($script:Provider.ListEntitlements($id))

            [void]$script:Provider.GrantEntitlement($id, $entitlement)

            $afterGrant = @($script:Provider.ListEntitlements($id))

            [void]$script:Provider.RevokeEntitlement($id, $entitlement)

            $afterRevoke = @($script:Provider.ListEntitlements($id))

            # Sanity: arrays (may be empty). Do NOT use pipeline with empty arrays in Pester.
            ($before -is [object[]]) | Should -BeTrue
            ($afterGrant -is [object[]]) | Should -BeTrue
            ($afterRevoke -is [object[]]) | Should -BeTrue

            # After grant, the entitlement must be present (by Kind+Id).
            ($afterGrant | Where-Object { $_.Kind -eq $entitlement.Kind -and $_.Id -eq $entitlement.Id }).Count | Should -Be 1

            # After revoke, it must be absent.
            ($afterRevoke | Where-Object { $_.Kind -eq $entitlement.Kind -and $_.Id -eq $entitlement.Id }).Count | Should -Be 0
        }
    }
}

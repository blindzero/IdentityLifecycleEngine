Set-StrictMode -Version Latest

function Invoke-IdleEntitlementProviderContractTests {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [scriptblock] $NewProvider,

        [Parameter()]
        [string] $ProviderLabel = 'Entitlement provider'
    )

    $cases = @(
        @{
            ProviderFactory = $NewProvider
        }
    )

    Context "$ProviderLabel contract" -ForEach $cases {
        BeforeAll {
            $providerFactory = $_.ProviderFactory

            if ($null -eq $providerFactory) {
                throw 'NewProvider scriptblock is required for entitlement provider contract tests.'
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

            $before = @($script:Provider.ListEntitlements($id))

            [void]$script:Provider.GrantEntitlement($id, $entitlement)
            $afterGrant = @($script:Provider.ListEntitlements($id))

            [void]$script:Provider.RevokeEntitlement($id, $entitlement)
            $afterRevoke = @($script:Provider.ListEntitlements($id))

            ($afterGrant | Where-Object { $_.Kind -eq $entitlement.Kind -and $_.Id -eq $entitlement.Id }).Count | Should -Be 1
            ($afterRevoke | Where-Object { $_.Kind -eq $entitlement.Kind -and $_.Id -eq $entitlement.Id }).Count | Should -Be 0

            # Sanity: $null is treated as empty.
            ($before -is [object[]]) | Should -BeTrue
            ($afterGrant -is [object[]]) | Should -BeTrue
            ($afterRevoke -is [object[]]) | Should -BeTrue
        }
    }
}

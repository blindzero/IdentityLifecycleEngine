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

    Therefore the contract takes a provider factory scriptblock and creates the provider
    instance during runtime.

    Expected ScriptMethods on the provider object:
    - GetEntitlements(IdentityKey)
    - GrantEntitlement(IdentityKey, EntitlementId)
    - RevokeEntitlement(IdentityKey, EntitlementId)

    Behavioral rules:
    - GetEntitlements returns an array (may be empty).
    - GrantEntitlement and RevokeEntitlement are idempotent.
    - GrantEntitlement:
        - First call assigns -> Changed = $true
        - Second call on same assignment -> Changed = $false
    - RevokeEntitlement:
        - If not assigned -> Changed = $false
        - If assigned -> Changed = $true, and then Changed = $false on subsequent calls
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
        }

        It 'Exposes required methods' {
            $script:Provider.PSObject.Methods.Name | Should -Contain 'GetEntitlements'
            $script:Provider.PSObject.Methods.Name | Should -Contain 'GrantEntitlement'
            $script:Provider.PSObject.Methods.Name | Should -Contain 'RevokeEntitlement'
        }

        It 'GetEntitlements returns an array (possibly empty)' {
            $id = "contract-$([guid]::NewGuid().ToString('N'))"

            $items = @($script:Provider.GetEntitlements($id))

            # Must be enumerable and not $null.
            $items | Should -Not -BeNullOrEmpty -Because 'GetEntitlements must return an array; use @() for empty.'
        }

        It 'GetEntitlements items expose a stable minimal shape' {
            $id = "contract-$([guid]::NewGuid().ToString('N'))"

            $items = @($script:Provider.GetEntitlements($id))

            foreach ($e in $items) {
                # Minimal required field
                $e.PSObject.Properties.Name | Should -Contain 'Id'
                [string]$e.Id | Should -Not -BeNullOrEmpty

                # Optional-but-recommended fields (do not fail if absent)
                # Type, DisplayName are intentionally not required here to keep the contract flexible.
                if ($e.PSObject.Properties.Name -contains 'Type') {
                    [string]$e.Type | Should -Not -BeNullOrEmpty
                }
                if ($e.PSObject.Properties.Name -contains 'DisplayName') {
                    # DisplayName may be empty, but property must not be $null if present.
                    $null -eq $e.DisplayName | Should -BeFalse
                }
            }
        }

        It 'GrantEntitlement is idempotent and returns a Changed flag' {
            $id            = "contract-$([guid]::NewGuid().ToString('N'))"
            $entitlementId = "ent-$([guid]::NewGuid().ToString('N'))"

            $r1 = $script:Provider.GrantEntitlement($id, $entitlementId)
            $r2 = $script:Provider.GrantEntitlement($id, $entitlementId)

            $r1.PSObject.Properties.Name | Should -Contain 'Changed'
            $r1.Changed | Should -BeTrue

            $r2.PSObject.Properties.Name | Should -Contain 'Changed'
            $r2.Changed | Should -BeFalse
        }

        It 'RevokeEntitlement is idempotent and returns a Changed flag' {
            $id            = "contract-$([guid]::NewGuid().ToString('N'))"
            $entitlementId = "ent-$([guid]::NewGuid().ToString('N'))"

            # Revoke when nothing is assigned -> no change
            $r0 = $script:Provider.RevokeEntitlement($id, $entitlementId)
            $r0.PSObject.Properties.Name | Should -Contain 'Changed'
            $r0.Changed | Should -BeFalse

            # Assign then revoke -> change
            [void]$script:Provider.GrantEntitlement($id, $entitlementId)

            $r1 = $script:Provider.RevokeEntitlement($id, $entitlementId)
            $r2 = $script:Provider.RevokeEntitlement($id, $entitlementId)

            $r1.PSObject.Properties.Name | Should -Contain 'Changed'
            $r1.Changed | Should -BeTrue

            $r2.PSObject.Properties.Name | Should -Contain 'Changed'
            $r2.Changed | Should -BeFalse
        }
    }
}

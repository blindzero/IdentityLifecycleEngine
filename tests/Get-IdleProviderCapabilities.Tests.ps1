Set-StrictMode -Version Latest

BeforeDiscovery {
    . (Join-Path $PSScriptRoot '_testHelpers.ps1')
    Import-IdleTestModule
}

Describe 'IdLE.Core - Get-IdleProviderCapabilities (provider capability discovery)' {

    InModuleScope 'IdLE.Core' {

        BeforeAll {
            # Guard: ensure the helper is available inside the module scope.
            Get-Command Get-IdleProviderCapabilities -ErrorAction Stop | Out-Null
        }

        It 'returns explicitly advertised capabilities (sorted and unique)' {
            $provider = [pscustomobject]@{
                Name = 'TestProvider'
            }

            $provider | Add-Member -MemberType ScriptMethod -Name GetCapabilities -Value {
                return @(
                    'IdLE.Identity.Disable'
                    'IdLE.Identity.Read'
                    'IdLE.Identity.Read'            # duplicate on purpose
                    'IdLE.Identity.Attribute.Ensure'
                )
            } -Force

            $caps = Get-IdleProviderCapabilities -Provider $provider

            $caps | Should -Be @(
                'IdLE.Identity.Attribute.Ensure'
                'IdLE.Identity.Disable'
                'IdLE.Identity.Read'
            )
        }

        It 'throws when provider advertises invalid capability identifiers' {
            $provider = [pscustomobject]@{
                Name = 'BadProvider'
            }

            $provider | Add-Member -MemberType ScriptMethod -Name GetCapabilities -Value {
                return @(
                    'Identity Read'            # whitespace => invalid
                )
            } -Force

            { Get-IdleProviderCapabilities -Provider $provider } | Should -Throw
        }

        It 'returns an empty list when no GetCapabilities exists and inference is disabled' {
            $provider = [pscustomobject]@{
                Name = 'LegacyProvider'
            }

            # No GetCapabilities method here.

            $caps = Get-IdleProviderCapabilities -Provider $provider
            @($caps).Count | Should -Be 0
        }

        It 'can infer minimal capabilities when inference is enabled' {
            $provider = [pscustomobject]@{
                Name = 'LegacyProvider'
            }

            # Simulate a legacy provider by adding known methods.
            $provider | Add-Member -MemberType ScriptMethod -Name GetIdentity -Value { param([string] $IdentityKey) } -Force
            $provider | Add-Member -MemberType ScriptMethod -Name EnsureAttribute -Value { param([string] $IdentityKey, [string] $Name, [object] $Value) } -Force
            $provider | Add-Member -MemberType ScriptMethod -Name DisableIdentity -Value { param([string] $IdentityKey) } -Force
            $provider | Add-Member -MemberType ScriptMethod -Name ListEntitlements -Value { param([string] $IdentityKey) } -Force
            $provider | Add-Member -MemberType ScriptMethod -Name GrantEntitlement -Value { param([string] $IdentityKey, [object] $Entitlement) } -Force
            $provider | Add-Member -MemberType ScriptMethod -Name RevokeEntitlement -Value { param([string] $IdentityKey, [object] $Entitlement) } -Force

            $caps = Get-IdleProviderCapabilities -Provider $provider -AllowInference

            $caps | Should -Be @(
                'IdLE.Entitlement.Grant'
                'IdLE.Entitlement.List'
                'IdLE.Entitlement.Revoke'
                'IdLE.Identity.Attribute.Ensure'
                'IdLE.Identity.Disable'
                'IdLE.Identity.Read'
            )
        }

        It 'prefers explicit advertisement over inference when both are available' {
            $provider = [pscustomobject]@{
                Name = 'HybridProvider'
            }

            # Add legacy methods (would be inferred)
            $provider | Add-Member -MemberType ScriptMethod -Name GetIdentity -Value { param([string] $IdentityKey) } -Force

            # Also add explicit GetCapabilities (must win)
            $provider | Add-Member -MemberType ScriptMethod -Name GetCapabilities -Value {
                return @('IdLE.Identity.Read')
            } -Force

            $caps = Get-IdleProviderCapabilities -Provider $provider -AllowInference

            $caps | Should -Be @('IdLE.Identity.Read')
        }

        It 'normalizes legacy capability names to canonical form' {
            $provider = [pscustomobject]@{
                Name = 'LegacyProvider'
            }

            $provider | Add-Member -MemberType ScriptMethod -Name GetCapabilities -Value {
                return @(
                    'Identity.Read'
                    'Identity.Disable'
                    'Identity.Attribute.Ensure'
                )
            } -Force

            $caps = Get-IdleProviderCapabilities -Provider $provider

            $caps | Should -Be @(
                'IdLE.Identity.Attribute.Ensure'
                'IdLE.Identity.Disable'
                'IdLE.Identity.Read'
            )
        }

        It 'normalizes mixed legacy and canonical capability names' {
            $provider = [pscustomobject]@{
                Name = 'MixedProvider'
            }

            $provider | Add-Member -MemberType ScriptMethod -Name GetCapabilities -Value {
                return @(
                    'Identity.Read'                    # legacy
                    'IdLE.Identity.Disable'            # canonical
                    'Identity.Attribute.Ensure'        # legacy
                    'IdLE.Entitlement.Grant'           # canonical
                )
            } -Force

            $caps = Get-IdleProviderCapabilities -Provider $provider

            $caps | Should -Be @(
                'IdLE.Entitlement.Grant'
                'IdLE.Identity.Attribute.Ensure'
                'IdLE.Identity.Disable'
                'IdLE.Identity.Read'
            )
        }
    }
}

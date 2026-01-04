Set-StrictMode -Version Latest

function Invoke-IdleIdentityProviderContractTests {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [scriptblock] $NewProvider,

        [Parameter()]
        [string] $ProviderLabel = 'Identity provider'
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
                throw 'NewProvider scriptblock is required for identity provider contract tests.'
            }

            $script:Provider = & $providerFactory
            if ($null -eq $script:Provider) {
                throw 'NewProvider returned $null. A provider instance is required for contract tests.'
            }
        }

        It 'Exposes required methods' {
            $script:Provider.PSObject.Methods.Name | Should -Contain 'GetIdentity'
            $script:Provider.PSObject.Methods.Name | Should -Contain 'EnsureAttribute'
            $script:Provider.PSObject.Methods.Name | Should -Contain 'DisableIdentity'
        }

        It 'GetIdentity returns an identity object with required keys/properties' {
            $id = "contract-$([guid]::NewGuid().ToString('N'))"
            $identity = $script:Provider.GetIdentity($id)

            $identity | Should -Not -BeNullOrEmpty

            if ($identity -is [hashtable]) {
                $identity.Keys | Should -Contain 'IdentityKey'
                $identity.Keys | Should -Contain 'Enabled'
                $identity.Keys | Should -Contain 'Attributes'

                $identity.IdentityKey | Should -Be $id
                $identity.Enabled | Should -BeOfType [bool]
                $identity.Attributes | Should -BeOfType [hashtable]
            }
            else {
                $identity.PSObject.Properties.Name | Should -Contain 'IdentityKey'
                $identity.PSObject.Properties.Name | Should -Contain 'Enabled'
                $identity.PSObject.Properties.Name | Should -Contain 'Attributes'

                $identity.IdentityKey | Should -Be $id
                $identity.Enabled | Should -BeOfType [bool]
                $identity.Attributes | Should -BeOfType [hashtable]
            }
        }

        It 'EnsureAttribute returns a stable result shape' {
            $id = "contract-$([guid]::NewGuid().ToString('N'))"

            $result = $script:Provider.EnsureAttribute($id, 'contractKey', 'contractValue')

            $result | Should -Not -BeNullOrEmpty
            $result.PSObject.Properties.Name | Should -Contain 'Changed'
            $result.PSObject.Properties.Name | Should -Contain 'IdentityKey'

            $result.IdentityKey | Should -Be $id
            $result.Changed | Should -BeOfType [bool]
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

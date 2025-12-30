Set-StrictMode -Version Latest

Describe 'IdLE.Provider.Mock - Mock identity provider' {

    BeforeAll {
        # Use a relative import from the current working directory (repo root) used by the test runner.
        # This keeps the test simple and avoids repo-root discovery issues in Pester discovery/runtime.
        $modulePath = Join-Path -Path (Get-Location).Path -ChildPath 'src\IdLE.Provider.Mock\IdLE.Provider.Mock.psd1'
        if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf)) {
            throw "Provider module manifest not found at: $modulePath"
        }

        Import-Module -Name $modulePath -Force -ErrorAction Stop
    }

    It 'Creates a provider instance' {
        $provider = New-IdleMockIdentityProvider

        $provider | Should -Not -BeNullOrEmpty
        $provider.Name | Should -Be 'MockIdentityProvider'
    }

    Context 'Provider contract (inline)' {

        BeforeAll {
            $script:Provider = New-IdleMockIdentityProvider
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

        It 'EnsureAttribute is idempotent' {
            $id = "contract-$([guid]::NewGuid().ToString('N'))"

            $r1 = $script:Provider.EnsureAttribute($id, 'Department', 'IT')
            $r2 = $script:Provider.EnsureAttribute($id, 'Department', 'IT')

            $r1.Changed | Should -BeTrue
            $r2.Changed | Should -BeFalse
        }

        It 'DisableIdentity is idempotent' {
            $id = "contract-$([guid]::NewGuid().ToString('N'))"

            $r1 = $script:Provider.DisableIdentity($id)
            $r2 = $script:Provider.DisableIdentity($id)

            $r1.Changed | Should -BeTrue
            $r2.Changed | Should -BeFalse
        }
    }

    It 'Keeps state scoped to the provider instance' {
        $p1 = New-IdleMockIdentityProvider
        $p2 = New-IdleMockIdentityProvider

        $null = $p1.EnsureAttribute('user1', 'Department', 'IT')

        $i1 = $p1.GetIdentity('user1')
        $i2 = $p2.GetIdentity('user1')

        $i1.Attributes['Department'] | Should -Be 'IT'
        $i2.Attributes.ContainsKey('Department') | Should -BeFalse
    }

    It 'Supports pre-seeded identities via InitialStore' {
        $provider = New-IdleMockIdentityProvider -InitialStore @{
            'user1' = @{
                IdentityKey = 'user1'
                Enabled     = $true
                Attributes  = @{ Department = 'HR' }
            }
        }

        $identity = $provider.GetIdentity('user1')
        $identity.Attributes['Department'] | Should -Be 'HR'

        $r = $provider.EnsureAttribute('user1', 'Department', 'HR')
        $r.Changed | Should -BeFalse
    }
}

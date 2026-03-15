Set-StrictMode -Version Latest

BeforeAll {
    . (Join-Path (Split-Path -Path $PSScriptRoot -Parent) '_testHelpers.ps1')
    Import-IdleTestModule

    . (Join-Path $PSScriptRoot '../../src/IdLE.Core/Private/Get-IdlePropertyValue.ps1')
}

Describe 'Get-IdlePropertyValue' {

    Context 'Basic property access' {
        It 'returns property value from PSCustomObject' {
            $obj = [pscustomobject]@{ Name = 'John'; Age = 30 }
            $result = Get-IdlePropertyValue -Object $obj -Name 'Name'
            $result | Should -Be 'John'
        }

        It 'returns property value from hashtable' {
            $obj = @{ Name = 'Jane'; Age = 25 }
            $result = Get-IdlePropertyValue -Object $obj -Name 'Name'
            $result | Should -Be 'Jane'
        }

        It 'returns null for non-existent property' {
            $obj = [pscustomobject]@{ Name = 'John' }
            $result = Get-IdlePropertyValue -Object $obj -Name 'Missing'
            $result | Should -BeNullOrEmpty
        }

        It 'returns null for non-existent key in hashtable' {
            $obj = @{ Name = 'John' }
            $result = Get-IdlePropertyValue -Object $obj -Name 'Missing'
            $result | Should -BeNullOrEmpty
        }

        It 'returns null when Object is null' {
            $result = Get-IdlePropertyValue -Object $null -Name 'Name'
            $result | Should -BeNullOrEmpty
        }
    }

    Context 'Member-access enumeration (array property access)' {
        It 'extracts property from all array items' {
            $list = @(
                [pscustomobject]@{ Kind = 'Group'; Id = 'g1' }
                [pscustomobject]@{ Kind = 'Group'; Id = 'g2' }
                [pscustomobject]@{ Kind = 'Group'; Id = 'g3' }
            )

            $result = Get-IdlePropertyValue -Object $list -Name 'Id'

            $result | Should -Not -BeNullOrEmpty
            $result.Count | Should -Be 3
            $result[0] | Should -Be 'g1'
            $result[1] | Should -Be 'g2'
            $result[2] | Should -Be 'g3'
        }

        It 'extracts Kind from entitlement objects' {
            $list = @(
                [pscustomobject]@{ Kind = 'Group'; Id = 'CN=Users,DC=example,DC=com' }
                [pscustomobject]@{ Kind = 'Group'; Id = 'CN=Admins,DC=example,DC=com' }
            )

            $result = Get-IdlePropertyValue -Object $list -Name 'Kind'

            $result | Should -Not -BeNullOrEmpty
            $result.Count | Should -Be 2
            $result[0] | Should -Be 'Group'
            $result[1] | Should -Be 'Group'
        }

        It 'returns null when array items do not have the property' {
            $list = @(
                [pscustomobject]@{ Name = 'John' }
                [pscustomobject]@{ Name = 'Jane' }
            )

            $result = Get-IdlePropertyValue -Object $list -Name 'Missing'

            $result | Should -BeNullOrEmpty
        }

        It 'returns null for empty array' {
            $list = @()

            $result = Get-IdlePropertyValue -Object $list -Name 'Id'

            $result | Should -BeNullOrEmpty
        }

        It 'handles arrays with null items gracefully' {
            $list = @(
                [pscustomobject]@{ Id = 'g1' }
                $null
                [pscustomobject]@{ Id = 'g3' }
            )

            $result = Get-IdlePropertyValue -Object $list -Name 'Id'

            $result | Should -Not -BeNullOrEmpty
            $result.Count | Should -Be 2
            $result[0] | Should -Be 'g1'
            $result[1] | Should -Be 'g3'
        }

        It 'extracts property from hashtable array items' {
            $list = @(
                @{ Kind = 'Group'; Id = 'g1' }
                @{ Kind = 'Group'; Id = 'g2' }
            )

            $result = Get-IdlePropertyValue -Object $list -Name 'Id'

            $result | Should -Not -BeNullOrEmpty
            $result.Count | Should -Be 2
            $result[0] | Should -Be 'g1'
            $result[1] | Should -Be 'g2'
        }
    }

    Context 'Edge cases' {
        It 'does not enumerate strings as character arrays' {
            $obj = [pscustomobject]@{ Name = 'Hello' }
            $result = Get-IdlePropertyValue -Object $obj -Name 'Name'

            $result | Should -Be 'Hello'
            $result | Should -BeOfType [string]
        }

        It 'returns scalar property when object has both the property and is enumerable' {
            # Edge case: object has both a direct property AND is enumerable
            $obj = New-Object System.Collections.ArrayList
            $obj.Add([pscustomobject]@{ Id = 'item1' }) | Out-Null
            $obj | Add-Member -NotePropertyName 'CustomProp' -NotePropertyValue 'CustomValue'

            # Should return the direct property, not enumerate
            $result = Get-IdlePropertyValue -Object $obj -Name 'CustomProp'

            $result | Should -Be 'CustomValue'
        }
    }
}

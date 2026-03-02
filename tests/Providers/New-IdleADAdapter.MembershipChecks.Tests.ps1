Set-StrictMode -Version Latest

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '..\_testHelpers.ps1')
    Import-IdleTestModule

    $repoRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    $adapterPath = Join-Path -Path $repoRoot -ChildPath 'src\IdLE.Provider.AD\Private\New-IdleADAdapter.ps1'
    
    if (-not (Test-Path -LiteralPath $adapterPath -PathType Leaf)) {
        throw "New-IdleADAdapter.ps1 not found at: $adapterPath"
    }

    # Mock the AD cmdlets globally for this test
    function Get-ADGroupMember {
        param($Identity, $Credential, $ErrorAction)
        
        # Simulate group membership data
        if ($script:MockGroupMembers.ContainsKey($Identity)) {
            return $script:MockGroupMembers[$Identity]
        }
        
        throw "Group '$Identity' not found"
    }

    function Add-ADGroupMember {
        param($Identity, $Members, $Credential, $ErrorAction)
        return
    }

    function Remove-ADGroupMember {
        param($Identity, $Members, $Confirm, $Credential, $ErrorAction)
        return
    }

    # Now source the adapter (which will use our mocked functions)
    . $adapterPath
}

Describe 'New-IdleADAdapter membership checks' {

    BeforeEach {
        $script:MockGroupMembers = @{}
    }

    Context 'TestGroupMembership method' {
        It 'returns $true when user is a member' {
            $script:MockGroupMembers['CN=TestGroup,DC=contoso,DC=com'] = @(
                [pscustomobject]@{ DistinguishedName = 'CN=User1,DC=contoso,DC=com' }
                [pscustomobject]@{ DistinguishedName = 'CN=User2,DC=contoso,DC=com' }
            )

            $adapter = New-IdleADAdapter
            $result = $adapter.TestGroupMembership('CN=TestGroup,DC=contoso,DC=com', 'CN=User1,DC=contoso,DC=com')
            
            $result | Should -Be $true
        }

        It 'returns $false when user is not a member' {
            $script:MockGroupMembers['CN=TestGroup,DC=contoso,DC=com'] = @(
                [pscustomobject]@{ DistinguishedName = 'CN=User1,DC=contoso,DC=com' }
            )

            $adapter = New-IdleADAdapter
            $result = $adapter.TestGroupMembership('CN=TestGroup,DC=contoso,DC=com', 'CN=User2,DC=contoso,DC=com')
            
            $result | Should -Be $false
        }

        It 'returns $null when Get-ADGroupMember fails' {
            # Don't add the group to MockGroupMembers, so Get-ADGroupMember will throw

            $adapter = New-IdleADAdapter
            $result = $adapter.TestGroupMembership('CN=NonExistentGroup,DC=contoso,DC=com', 'CN=User1,DC=contoso,DC=com')
            
            $result | Should -BeNullOrEmpty
        }

        It 'short-circuits after finding first match (performance)' {
            # Create a large group
            $members = @()
            for ($i = 1; $i -le 1000; $i++) {
                $members += [pscustomobject]@{ DistinguishedName = "CN=User$i,DC=contoso,DC=com" }
            }
            $script:MockGroupMembers['CN=LargeGroup,DC=contoso,DC=com'] = $members

            $adapter = New-IdleADAdapter
            # User1 is at the beginning - should find quickly
            $result = $adapter.TestGroupMembership('CN=LargeGroup,DC=contoso,DC=com', 'CN=User1,DC=contoso,DC=com')
            
            $result | Should -Be $true
        }
    }

    Context 'AddGroupMember change detection' {
        It 'returns $false when user is already a member (no-op)' {
            $script:MockGroupMembers['CN=TestGroup,DC=contoso,DC=com'] = @(
                [pscustomobject]@{ DistinguishedName = 'CN=User1,DC=contoso,DC=com' }
            )

            $adapter = New-IdleADAdapter
            $result = $adapter.AddGroupMember('CN=TestGroup,DC=contoso,DC=com', 'CN=User1,DC=contoso,DC=com')
            
            $result | Should -Be $false
        }

        It 'returns $true when user is added (change occurred)' {
            $script:MockGroupMembers['CN=TestGroup,DC=contoso,DC=com'] = @(
                [pscustomobject]@{ DistinguishedName = 'CN=User2,DC=contoso,DC=com' }
            )

            $adapter = New-IdleADAdapter
            $result = $adapter.AddGroupMember('CN=TestGroup,DC=contoso,DC=com', 'CN=User1,DC=contoso,DC=com')
            
            $result | Should -Be $true
        }

        It 'proceeds to Add-ADGroupMember when membership check fails (fail-forward)' {
            # Don't add the group to MockGroupMembers, so membership check will fail

            $adapter = New-IdleADAdapter
            $result = $adapter.AddGroupMember('CN=NonExistentGroup,DC=contoso,DC=com', 'CN=User1,DC=contoso,DC=com')
            
            $result | Should -Be $true
        }
    }

    Context 'RemoveGroupMember change detection' {
        It 'returns $false when user is not a member (no-op)' {
            $script:MockGroupMembers['CN=TestGroup,DC=contoso,DC=com'] = @(
                [pscustomobject]@{ DistinguishedName = 'CN=User2,DC=contoso,DC=com' }
            )

            $adapter = New-IdleADAdapter
            $result = $adapter.RemoveGroupMember('CN=TestGroup,DC=contoso,DC=com', 'CN=User1,DC=contoso,DC=com')
            
            $result | Should -Be $false
        }

        It 'returns $true when user is removed (change occurred)' {
            $script:MockGroupMembers['CN=TestGroup,DC=contoso,DC=com'] = @(
                [pscustomobject]@{ DistinguishedName = 'CN=User1,DC=contoso,DC=com' }
            )

            $adapter = New-IdleADAdapter
            $result = $adapter.RemoveGroupMember('CN=TestGroup,DC=contoso,DC=com', 'CN=User1,DC=contoso,DC=com')
            
            $result | Should -Be $true
        }

        It 'proceeds to Remove-ADGroupMember when membership check fails (fail-forward)' {
            # Don't add the group to MockGroupMembers, so membership check will fail

            $adapter = New-IdleADAdapter
            $result = $adapter.RemoveGroupMember('CN=NonExistentGroup,DC=contoso,DC=com', 'CN=User1,DC=contoso,DC=com')
            
            $result | Should -Be $true
        }
    }

    Context 'Idempotency across multiple calls' {
        It 'AddGroupMember is idempotent - second call returns $false' {
            $script:MockGroupMembers['CN=TestGroup,DC=contoso,DC=com'] = @()

            $adapter = New-IdleADAdapter
            
            # First call - should add
            $result1 = $adapter.AddGroupMember('CN=TestGroup,DC=contoso,DC=com', 'CN=User1,DC=contoso,DC=com')
            $result1 | Should -Be $true

            # Simulate the user now being a member
            $script:MockGroupMembers['CN=TestGroup,DC=contoso,DC=com'] = @(
                [pscustomobject]@{ DistinguishedName = 'CN=User1,DC=contoso,DC=com' }
            )

            # Second call - should be no-op
            $result2 = $adapter.AddGroupMember('CN=TestGroup,DC=contoso,DC=com', 'CN=User1,DC=contoso,DC=com')
            $result2 | Should -Be $false
        }

        It 'RemoveGroupMember is idempotent - second call returns $false' {
            $script:MockGroupMembers['CN=TestGroup,DC=contoso,DC=com'] = @(
                [pscustomobject]@{ DistinguishedName = 'CN=User1,DC=contoso,DC=com' }
            )

            $adapter = New-IdleADAdapter
            
            # First call - should remove
            $result1 = $adapter.RemoveGroupMember('CN=TestGroup,DC=contoso,DC=com', 'CN=User1,DC=contoso,DC=com')
            $result1 | Should -Be $true

            # Simulate the user no longer being a member
            $script:MockGroupMembers['CN=TestGroup,DC=contoso,DC=com'] = @()

            # Second call - should be no-op
            $result2 = $adapter.RemoveGroupMember('CN=TestGroup,DC=contoso,DC=com', 'CN=User1,DC=contoso,DC=com')
            $result2 | Should -Be $false
        }
    }
}

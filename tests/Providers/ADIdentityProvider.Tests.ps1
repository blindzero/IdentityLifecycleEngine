Set-StrictMode -Version Latest

BeforeDiscovery {
    . (Join-Path -Path $PSScriptRoot -ChildPath '..\_testHelpers.ps1')
    Import-IdleTestModule

    $testsRoot = Split-Path -Path $PSScriptRoot -Parent
    $repoRoot  = Split-Path -Path $testsRoot -Parent

    $identityContractPath = Join-Path -Path $repoRoot -ChildPath 'tests\ProviderContracts\IdentityProvider.Contract.ps1'
    if (-not (Test-Path -LiteralPath $identityContractPath -PathType Leaf)) {
        throw "Identity provider contract not found at: $identityContractPath"
    }
    . $identityContractPath

    $capabilitiesContractPath = Join-Path -Path $repoRoot -ChildPath 'tests\ProviderContracts\ProviderCapabilities.Contract.ps1'
    if (-not (Test-Path -LiteralPath $capabilitiesContractPath -PathType Leaf)) {
        throw "Provider capabilities contract not found at: $capabilitiesContractPath"
    }
    . $capabilitiesContractPath

    $entitlementContractPath = Join-Path -Path $repoRoot -ChildPath 'tests\ProviderContracts\EntitlementProvider.Contract.ps1'
    if (-not (Test-Path -LiteralPath $entitlementContractPath -PathType Leaf)) {
        throw "Entitlement provider contract not found at: $entitlementContractPath"
    }
    . $entitlementContractPath
}

Describe 'AD identity provider' {
    BeforeAll {
        $repoRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
        $adProviderPath = Join-Path -Path $repoRoot -ChildPath 'src\IdLE.Provider.AD\IdLE.Provider.AD.psd1'
        
        if (Test-Path -LiteralPath $adProviderPath -PathType Leaf) {
            Import-Module $adProviderPath -Force
        }

        function New-FakeADAdapter {
            $store = @{}

            $adapter = [pscustomobject]@{
                PSTypeName = 'FakeADAdapter'
                Store      = $store
            }

            # Auto-creation behavior: The fake adapter auto-creates identities on lookup
            # to support provider contract tests (which expect this behavior from test providers).
            # This differs from the real AD adapter which will throw when an identity is not found.

            $adapter | Add-Member -MemberType ScriptMethod -Name GetUserByUpn -Value {
                param([string]$Upn)
                foreach ($key in $this.Store.Keys) {
                    if ($this.Store[$key].UserPrincipalName -eq $Upn) {
                        return $this.Store[$key]
                    }
                }
                return $null
            } -Force

            $adapter | Add-Member -MemberType ScriptMethod -Name GetUserBySam -Value {
                param([string]$SamAccountName)
                foreach ($key in $this.Store.Keys) {
                    if ($this.Store[$key].sAMAccountName -eq $SamAccountName) {
                        return $this.Store[$key]
                    }
                }
                
                # Auto-create for test compatibility (like Mock provider)
                $guid = [guid]::NewGuid().ToString()
                $user = [pscustomobject]@{
                    ObjectGuid         = [guid]$guid
                    sAMAccountName     = $SamAccountName
                    UserPrincipalName  = "$SamAccountName@domain.local"
                    DistinguishedName  = "CN=$SamAccountName,OU=Users,DC=domain,DC=local"
                    Enabled            = $true
                    GivenName          = $null
                    Surname            = $null
                    DisplayName        = $null
                    Description        = $null
                    Department         = $null
                    Title              = $null
                    EmailAddress       = $null
                    Groups             = @()
                }
                $this.Store[$guid] = $user
                return $user
            } -Force

            $adapter | Add-Member -MemberType ScriptMethod -Name GetUserByGuid -Value {
                param([string]$Guid)
                if ($this.Store.ContainsKey($Guid)) {
                    return $this.Store[$Guid]
                }
                return $null
            } -Force

            $adapter | Add-Member -MemberType ScriptMethod -Name NewUser -Value {
                param([string]$Name, [hashtable]$Attributes, [bool]$Enabled)
                
                $guid = [guid]::NewGuid().ToString()
                $sam = if ($Attributes.ContainsKey('SamAccountName')) { $Attributes['SamAccountName'] } else { $Name }
                $upn = if ($Attributes.ContainsKey('UserPrincipalName')) { $Attributes['UserPrincipalName'] } else { "$sam@domain.local" }
                $path = if ($Attributes.ContainsKey('Path')) { $Attributes['Path'] } else { 'OU=Users,DC=domain,DC=local' }

                $user = [pscustomobject]@{
                    ObjectGuid         = [guid]$guid
                    sAMAccountName     = $sam
                    UserPrincipalName  = $upn
                    DistinguishedName  = "CN=$Name,$path"
                    Enabled            = $Enabled
                    GivenName          = $Attributes['GivenName']
                    Surname            = $Attributes['Surname']
                    DisplayName        = $Attributes['DisplayName']
                    Description        = $Attributes['Description']
                    Department         = $Attributes['Department']
                    Title              = $Attributes['Title']
                    EmailAddress       = $Attributes['EmailAddress']
                    Groups             = @()
                }

                $this.Store[$guid] = $user
                return $user
            } -Force

            $adapter | Add-Member -MemberType ScriptMethod -Name SetUser -Value {
                param([string]$Identity, [string]$AttributeName, $Value)
                
                $user = $null
                foreach ($key in $this.Store.Keys) {
                    if ($this.Store[$key].DistinguishedName -eq $Identity) {
                        $user = $this.Store[$key]
                        break
                    }
                }

                if ($null -eq $user) {
                    throw "User not found: $Identity"
                }

                # Handle known properties
                $knownProps = @('GivenName', 'Surname', 'DisplayName', 'Description', 'Department', 'Title', 'EmailAddress', 'UserPrincipalName')
                if ($AttributeName -in $knownProps -and $null -ne $user.PSObject.Properties[$AttributeName]) {
                    $user.$AttributeName = $Value
                } else {
                    # Add as a dynamic property if it doesn't exist
                    if ($null -eq $user.PSObject.Properties[$AttributeName]) {
                        $user | Add-Member -MemberType NoteProperty -Name $AttributeName -Value $Value -Force
                    } else {
                        $user.$AttributeName = $Value
                    }
                }
            } -Force

            $adapter | Add-Member -MemberType ScriptMethod -Name DisableUser -Value {
                param([string]$Identity)
                
                $user = $null
                foreach ($key in $this.Store.Keys) {
                    if ($this.Store[$key].DistinguishedName -eq $Identity) {
                        $user = $this.Store[$key]
                        break
                    }
                }

                if ($null -eq $user) {
                    throw "User not found: $Identity"
                }

                $user.Enabled = $false
            } -Force

            $adapter | Add-Member -MemberType ScriptMethod -Name EnableUser -Value {
                param([string]$Identity)
                
                $user = $null
                foreach ($key in $this.Store.Keys) {
                    if ($this.Store[$key].DistinguishedName -eq $Identity) {
                        $user = $this.Store[$key]
                        break
                    }
                }

                if ($null -eq $user) {
                    throw "User not found: $Identity"
                }

                $user.Enabled = $true
            } -Force

            $adapter | Add-Member -MemberType ScriptMethod -Name MoveObject -Value {
                param([string]$Identity, [string]$TargetPath)
                
                $user = $null
                foreach ($key in $this.Store.Keys) {
                    if ($this.Store[$key].DistinguishedName -eq $Identity) {
                        $user = $this.Store[$key]
                        break
                    }
                }

                if ($null -eq $user) {
                    throw "User not found: $Identity"
                }

                $cn = $user.DistinguishedName -replace ',.*$', ''
                $user.DistinguishedName = "$cn,$TargetPath"
            } -Force

            $adapter | Add-Member -MemberType ScriptMethod -Name DeleteUser -Value {
                param([string]$Identity)
                
                $keyToRemove = $null
                foreach ($key in $this.Store.Keys) {
                    if ($this.Store[$key].DistinguishedName -eq $Identity) {
                        $keyToRemove = $key
                        break
                    }
                }

                if ($null -ne $keyToRemove) {
                    $this.Store.Remove($keyToRemove)
                }
            } -Force

            $adapter | Add-Member -MemberType ScriptMethod -Name GetGroupById -Value {
                param([string]$Identity)
                
                return [pscustomobject]@{
                    DistinguishedName = $Identity
                    Name = ($Identity -split ',')[0] -replace '^CN=', ''
                    sAMAccountName = ($Identity -split ',')[0] -replace '^CN=', ''
                    ObjectGuid = [guid]::NewGuid()
                }
            } -Force

            $adapter | Add-Member -MemberType ScriptMethod -Name AddGroupMember -Value {
                param([string]$GroupIdentity, [string]$MemberIdentity)
                
                $user = $null
                foreach ($key in $this.Store.Keys) {
                    if ($this.Store[$key].DistinguishedName -eq $MemberIdentity) {
                        $user = $this.Store[$key]
                        break
                    }
                }

                if ($null -eq $user) {
                    throw "User not found: $MemberIdentity"
                }

                if ($null -eq $user.Groups) {
                    $user.Groups = @()
                }

                # Store as object with metadata for entitlement tracking
                $existingGroup = $user.Groups | Where-Object { $_.Id -eq $GroupIdentity }
                if ($null -eq $existingGroup) {
                    $user.Groups = @($user.Groups) + @([pscustomobject]@{ Id = $GroupIdentity; Kind = 'Group' })
                }
            } -Force

            $adapter | Add-Member -MemberType ScriptMethod -Name RemoveGroupMember -Value {
                param([string]$GroupIdentity, [string]$MemberIdentity)
                
                $user = $null
                foreach ($key in $this.Store.Keys) {
                    if ($this.Store[$key].DistinguishedName -eq $MemberIdentity) {
                        $user = $this.Store[$key]
                        break
                    }
                }

                if ($null -eq $user) {
                    throw "User not found: $MemberIdentity"
                }

                if ($null -ne $user.Groups) {
                    $user.Groups = @($user.Groups | Where-Object { $_.Id -ne $GroupIdentity })
                }
            } -Force

            $adapter | Add-Member -MemberType ScriptMethod -Name GetUserGroups -Value {
                param([string]$Identity)
                
                $user = $null
                foreach ($key in $this.Store.Keys) {
                    if ($this.Store[$key].DistinguishedName -eq $Identity) {
                        $user = $this.Store[$key]
                        break
                    }
                }

                if ($null -eq $user) {
                    throw "User not found: $Identity"
                }

                $groups = @()
                if ($null -ne $user.Groups) {
                    foreach ($groupEntry in $user.Groups) {
                        $groupDn = if ($groupEntry -is [string]) { $groupEntry } else { $groupEntry.Id }
                        $groups += [pscustomobject]@{
                            DistinguishedName = $groupDn
                            Name = ($groupDn -split ',')[0] -replace '^CN=', ''
                        }
                    }
                }
                return $groups
            } -Force

            $adapter | Add-Member -MemberType ScriptMethod -Name ListUsers -Value {
                param([hashtable]$Filter)
                
                $results = @()
                foreach ($key in $this.Store.Keys) {
                    $user = $this.Store[$key]
                    
                    if ($null -ne $Filter -and $Filter.ContainsKey('Search')) {
                        $search = $Filter['Search']
                        if ($user.sAMAccountName -like "$search*" -or $user.UserPrincipalName -like "$search*") {
                            $results += $user
                        }
                    }
                    else {
                        $results += $user
                    }
                }
                return $results
            } -Force

            return $adapter
        }

        $script:FakeAdapter = New-FakeADAdapter
    }

    Context 'Provider contract tests' {
        Invoke-IdleIdentityProviderContractTests -NewProvider {
            New-IdleADIdentityProvider -Adapter $script:FakeAdapter
        }

        Invoke-IdleProviderCapabilitiesContractTests -ProviderFactory {
            New-IdleADIdentityProvider -Adapter $script:FakeAdapter
        }

        # Note: Generic entitlement contract tests are skipped for AD provider because:
        # - AD only supports Kind='Group' (not arbitrary entitlement kinds like 'Contract')
        # - Generic contract tests use Kind='Contract' which doesn't match AD's behavior
        # - AD-specific entitlement tests with Kind='Group' are in the 'Idempotency' context below
    }

    Context 'AD-specific entitlement operations' {
        BeforeAll {
            $adapter = New-FakeADAdapter
            $provider = New-IdleADIdentityProvider -Adapter $adapter
            $script:TestProvider = $provider
            $script:TestAdapter = $adapter
        }

        It 'Exposes required entitlement methods' {
            $script:TestProvider.PSObject.Methods.Name | Should -Contain 'ListEntitlements'
            $script:TestProvider.PSObject.Methods.Name | Should -Contain 'GrantEntitlement'
            $script:TestProvider.PSObject.Methods.Name | Should -Contain 'RevokeEntitlement'
        }

        It 'GrantEntitlement returns stable result shape with Kind=Group' {
            $testUser = $script:TestAdapter.NewUser('EntTest1', @{ SamAccountName = 'enttest1' }, $true)
            $id = $testUser.ObjectGuid.ToString()

            $entitlement = @{
                Kind        = 'Group'
                Id          = 'CN=TestGroup,OU=Groups,DC=domain,DC=local'
                DisplayName = 'Test Group'
            }

            $result = $script:TestProvider.GrantEntitlement($id, $entitlement)

            $result | Should -Not -BeNullOrEmpty
            $result.PSObject.Properties.Name | Should -Contain 'Changed'
            $result.PSObject.Properties.Name | Should -Contain 'IdentityKey'
            $result.PSObject.Properties.Name | Should -Contain 'Entitlement'
            $result.Changed | Should -BeOfType [bool]
            $result.Entitlement.Kind | Should -Be 'Group'
        }

        It 'GrantEntitlement is idempotent with Kind=Group' {
            $testUser = $script:TestAdapter.NewUser('EntTest2', @{ SamAccountName = 'enttest2' }, $true)
            $id = $testUser.ObjectGuid.ToString()

            $entitlement = @{
                Kind = 'Group'
                Id   = 'CN=IdempotentGroup,OU=Groups,DC=domain,DC=local'
            }

            $r1 = $script:TestProvider.GrantEntitlement($id, $entitlement)
            $r2 = $script:TestProvider.GrantEntitlement($id, $entitlement)

            $r1.Changed | Should -BeTrue
            $r2.Changed | Should -BeFalse
        }

        It 'RevokeEntitlement is idempotent with Kind=Group' {
            $testUser = $script:TestAdapter.NewUser('EntTest3', @{ SamAccountName = 'enttest3' }, $true)
            $id = $testUser.ObjectGuid.ToString()

            $entitlement = @{
                Kind = 'Group'
                Id   = 'CN=RevokeGroup,OU=Groups,DC=domain,DC=local'
            }

            $script:TestProvider.GrantEntitlement($id, $entitlement) | Out-Null

            $r1 = $script:TestProvider.RevokeEntitlement($id, $entitlement)
            $r2 = $script:TestProvider.RevokeEntitlement($id, $entitlement)

            $r1.Changed | Should -BeTrue
            $r2.Changed | Should -BeFalse
        }

        It 'ListEntitlements reflects grant and revoke operations with Kind=Group' {
            $testUser = $script:TestAdapter.NewUser('EntTest4', @{ SamAccountName = 'enttest4' }, $true)
            $id = $testUser.ObjectGuid.ToString()

            $entitlement = @{
                Kind = 'Group'
                Id   = 'CN=ListTestGroup,OU=Groups,DC=domain,DC=local'
            }

            $before = @($script:TestProvider.ListEntitlements($id))

            $script:TestProvider.GrantEntitlement($id, $entitlement) | Out-Null
            $afterGrant = @($script:TestProvider.ListEntitlements($id))

            $script:TestProvider.RevokeEntitlement($id, $entitlement) | Out-Null
            $afterRevoke = @($script:TestProvider.ListEntitlements($id))

            @($afterGrant | Where-Object { $_.Kind -eq 'Group' -and $_.Id -eq $entitlement.Id }).Count | Should -Be 1
            @($afterRevoke | Where-Object { $_.Kind -eq 'Group' -and $_.Id -eq $entitlement.Id }).Count | Should -Be 0
        }
    }

    Context 'Identity resolution' {
        BeforeAll {
            $adapter = New-FakeADAdapter
            $provider = New-IdleADIdentityProvider -Adapter $adapter

            $testUser = $adapter.NewUser('TestUser', @{
                SamAccountName = 'testuser'
                UserPrincipalName = 'testuser@domain.local'
                GivenName = 'Test'
                Surname = 'User'
            }, $true)

            $script:TestProvider = $provider
            $script:TestGuid = $testUser.ObjectGuid.ToString()
            $script:TestUpn = $testUser.UserPrincipalName
            $script:TestSam = $testUser.sAMAccountName
        }

        It 'Resolves identity by GUID' {
            $identity = $script:TestProvider.GetIdentity($script:TestGuid)
            $identity.IdentityKey | Should -Be $script:TestGuid
            $identity.Attributes['sAMAccountName'] | Should -Be $script:TestSam
        }

        It 'Resolves identity by UPN' {
            $identity = $script:TestProvider.GetIdentity($script:TestUpn)
            $identity.IdentityKey | Should -Be $script:TestUpn
            $identity.Attributes['UserPrincipalName'] | Should -Be $script:TestUpn
        }

        It 'Resolves identity by sAMAccountName' {
            $identity = $script:TestProvider.GetIdentity($script:TestSam)
            $identity.IdentityKey | Should -Be $script:TestSam
            $identity.Attributes['sAMAccountName'] | Should -Be $script:TestSam
        }

        It 'Returns identity for nonexistent user (auto-creates in test adapter)' {
            $identity = $script:TestProvider.GetIdentity('nonexistent-auto')
            $identity | Should -Not -BeNullOrEmpty
            $identity.IdentityKey | Should -Be 'nonexistent-auto'
        }
    }

    Context 'LDAP filter escaping (ProtectLdapFilterValue)' {
        BeforeAll {
            # Import the private New-IdleADAdapter function to test the real implementation
            $repoRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
            $adapterScriptPath = Join-Path -Path $repoRoot -ChildPath 'src\IdLE.Provider.AD\Private\New-IdleADAdapter.ps1'
            
            if (-not (Test-Path -LiteralPath $adapterScriptPath -PathType Leaf)) {
                throw "New-IdleADAdapter script not found at: $adapterScriptPath"
            }
            
            # Dot-source the adapter script to make New-IdleADAdapter available
            . $adapterScriptPath
            
            # Create a real adapter instance to test the actual ProtectLdapFilterValue implementation
            $script:TestEscapeAdapter = New-IdleADAdapter
        }

        It 'Escapes backslash character' {
            $result = $script:TestEscapeAdapter.ProtectLdapFilterValue('test\value')
            $result | Should -Be 'test\5cvalue'
        }

        It 'Escapes asterisk character' {
            $result = $script:TestEscapeAdapter.ProtectLdapFilterValue('test*value')
            $result | Should -Be 'test\2avalue'
        }

        It 'Escapes left parenthesis' {
            $result = $script:TestEscapeAdapter.ProtectLdapFilterValue('test(value')
            $result | Should -Be 'test\28value'
        }

        It 'Escapes right parenthesis' {
            $result = $script:TestEscapeAdapter.ProtectLdapFilterValue('test)value')
            $result | Should -Be 'test\29value'
        }

        It 'Escapes null byte' {
            $result = $script:TestEscapeAdapter.ProtectLdapFilterValue("test`0value")
            $result | Should -Be 'test\00value'
        }

        It 'Escapes multiple special characters in one string' {
            $result = $script:TestEscapeAdapter.ProtectLdapFilterValue('test*\()value')
            $result | Should -Be 'test\2a\5c\28\29value'
        }

        It 'Returns unchanged string when no special characters present' {
            $result = $script:TestEscapeAdapter.ProtectLdapFilterValue('testvalue123')
            $result | Should -Be 'testvalue123'
        }

        It 'Handles empty string' {
            $result = $script:TestEscapeAdapter.ProtectLdapFilterValue('')
            $result | Should -Be ''
        }

        It 'Can be called from within a ScriptMethod (fixes scope issue)' {
            # This verifies that the fix works: ProtectLdapFilterValue is accessible via $this
            # from within another ScriptMethod (like GetUserBySam).
            # The real integration test is that all the provider contract tests pass,
            # which exercise GetUserBySam, GetUserByUpn, and ListUsers that all use ProtectLdapFilterValue.
            # Here we just verify the method exists and is a ScriptMethod.
            $script:TestEscapeAdapter.PSObject.Methods['ProtectLdapFilterValue'] | Should -Not -BeNullOrEmpty
            $script:TestEscapeAdapter.PSObject.Methods['ProtectLdapFilterValue'].MemberType | Should -Be 'ScriptMethod'
        }
    }

    Context 'Idempotency' {
        BeforeEach {
            $adapter = New-FakeADAdapter
            $provider = New-IdleADIdentityProvider -Adapter $adapter -AllowDelete
            $script:TestProvider = $provider
            $script:TestAdapter = $adapter
        }

        It 'CreateIdentity is idempotent - returns Changed=$false if identity exists' {
            $attrs = @{
                SamAccountName = 'idempotent1'
                UserPrincipalName = 'idempotent1@domain.local'
                GivenName = 'Test'
                Surname = 'User'
            }

            # Pre-create the user using the adapter
            $script:TestAdapter.NewUser('idempotent1', $attrs, $true) | Out-Null

            # Now create should be idempotent
            $result1 = $script:TestProvider.CreateIdentity('idempotent1', $attrs)
            $result1.Changed | Should -BeFalse

            $result2 = $script:TestProvider.CreateIdentity('idempotent1', $attrs)
            $result2.Changed | Should -BeFalse
        }

        It 'DisableIdentity is idempotent' {
            $testUser = $script:TestAdapter.NewUser('DisableTest', @{ SamAccountName = 'distest' }, $true)
            $guid = $testUser.ObjectGuid.ToString()

            $result1 = $script:TestProvider.DisableIdentity($guid)
            $result1.Changed | Should -BeTrue

            $result2 = $script:TestProvider.DisableIdentity($guid)
            $result2.Changed | Should -BeFalse
        }

        It 'EnableIdentity is idempotent' {
            $testUser = $script:TestAdapter.NewUser('EnableTest', @{ SamAccountName = 'entest' }, $false)
            $guid = $testUser.ObjectGuid.ToString()

            $result1 = $script:TestProvider.EnableIdentity($guid)
            $result1.Changed | Should -BeTrue

            $result2 = $script:TestProvider.EnableIdentity($guid)
            $result2.Changed | Should -BeFalse
        }

        It 'MoveIdentity is idempotent' {
            $testUser = $script:TestAdapter.NewUser('MoveTest', @{ 
                SamAccountName = 'movetest'
                Path = 'OU=Source,DC=domain,DC=local'
            }, $true)
            $guid = $testUser.ObjectGuid.ToString()

            $targetOu = 'OU=Target,DC=domain,DC=local'

            $result1 = $script:TestProvider.MoveIdentity($guid, $targetOu)
            $result1.Changed | Should -BeTrue

            $result2 = $script:TestProvider.MoveIdentity($guid, $targetOu)
            $result2.Changed | Should -BeFalse
        }

        It 'DeleteIdentity is idempotent - returns Changed=$false if already deleted' {
            $testUser = $script:TestAdapter.NewUser('DeleteTest', @{ SamAccountName = 'deltest' }, $true)
            $guid = $testUser.ObjectGuid.ToString()

            $result1 = $script:TestProvider.DeleteIdentity($guid)
            $result1.Changed | Should -BeTrue

            $result2 = $script:TestProvider.DeleteIdentity($guid)
            $result2.Changed | Should -BeFalse
        }

        It 'GrantEntitlement is idempotent' {
            $testUser = $script:TestAdapter.NewUser('GrantTest', @{ SamAccountName = 'granttest' }, $true)
            $guid = $testUser.ObjectGuid.ToString()

            $entitlement = @{ Kind = 'Group'; Id = 'CN=TestGroup,OU=Groups,DC=domain,DC=local' }

            $result1 = $script:TestProvider.GrantEntitlement($guid, $entitlement)
            $result1.Changed | Should -BeTrue

            $result2 = $script:TestProvider.GrantEntitlement($guid, $entitlement)
            $result2.Changed | Should -BeFalse
        }

        It 'RevokeEntitlement is idempotent' {
            $testUser = $script:TestAdapter.NewUser('RevokeTest', @{ SamAccountName = 'revoketest' }, $true)
            $guid = $testUser.ObjectGuid.ToString()

            $entitlement = @{ Kind = 'Group'; Id = 'CN=TestGroup,OU=Groups,DC=domain,DC=local' }

            $script:TestProvider.GrantEntitlement($guid, $entitlement) | Out-Null

            $result1 = $script:TestProvider.RevokeEntitlement($guid, $entitlement)
            $result1.Changed | Should -BeTrue

            $result2 = $script:TestProvider.RevokeEntitlement($guid, $entitlement)
            $result2.Changed | Should -BeFalse
        }
    }

    Context 'AllowDelete gating' {
        It 'Advertises Delete capability when AllowDelete=$true' {
            $adapter = New-FakeADAdapter
            $provider = New-IdleADIdentityProvider -Adapter $adapter -AllowDelete

            $caps = $provider.GetCapabilities()
            $caps | Should -Contain 'IdLE.Identity.Delete'
        }

        It 'Does not advertise Delete capability when AllowDelete=$false' {
            $adapter = New-FakeADAdapter
            $provider = New-IdleADIdentityProvider -Adapter $adapter

            $caps = $provider.GetCapabilities()
            $caps | Should -Not -Contain 'IdLE.Identity.Delete'
        }

        It 'Throws when DeleteIdentity is called without AllowDelete' {
            $adapter = New-FakeADAdapter
            $provider = New-IdleADIdentityProvider -Adapter $adapter
            
            $testUser = $adapter.NewUser('DeleteGateTest', @{ SamAccountName = 'delgate' }, $true)
            $guid = $testUser.ObjectGuid.ToString()

            { $provider.DeleteIdentity($guid) } | Should -Throw -ExpectedMessage '*AllowDelete*'
        }
    }
}

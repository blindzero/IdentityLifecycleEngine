Set-StrictMode -Version Latest

BeforeDiscovery {
    . (Join-Path -Path $PSScriptRoot -ChildPath '..\_testHelpers.ps1')
    Import-IdleTestModule

    $testsRoot = Split-Path -Path $PSScriptRoot -Parent
    $repoRoot = Split-Path -Path $testsRoot -Parent

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

    # Import EntraID provider
    $entraIDModulePath = Join-Path -Path $repoRoot -ChildPath 'src\IdLE.Provider.EntraID\IdLE.Provider.EntraID.psm1'
    if (-not (Test-Path -LiteralPath $entraIDModulePath -PathType Leaf)) {
        throw "EntraID provider module not found at: $entraIDModulePath"
    }
    Import-Module $entraIDModulePath -Force
}

Describe 'EntraID identity provider - Contract tests' {
    BeforeAll {
        # Create a fake adapter for contract tests
        $fakeAdapter = [pscustomobject]@{
            PSTypeName = 'IdLE.EntraIDAdapter.Fake'
            Store      = @{}
        }

        $fakeAdapter | Add-Member -MemberType ScriptMethod -Name GetUserById -Value {
            param($ObjectId, $AccessToken)
            $key = "id:$ObjectId"
            if (-not $this.Store.ContainsKey($key)) {
                $this.Store[$key] = @{
                    id             = $ObjectId
                    userPrincipalName = "$ObjectId@test.local"
                    mail           = "$ObjectId@test.local"
                    displayName    = "User $ObjectId"
                    accountEnabled = $true
                    givenName      = "Test"
                    surname        = "User"
                }
            }
            return $this.Store[$key]
        }

        $fakeAdapter | Add-Member -MemberType ScriptMethod -Name GetUserByUpn -Value {
            param($Upn, $AccessToken)
            # Try direct lookup first
            if ($this.Store.ContainsKey("upn:$Upn")) {
                return $this.Store["upn:$Upn"]
            }
            # Fallback to search (for backwards compatibility)
            foreach ($key in $this.Store.Keys) {
                if ($this.Store[$key].userPrincipalName -eq $Upn) {
                    return $this.Store[$key]
                }
            }
            return $null
        }

        $fakeAdapter | Add-Member -MemberType ScriptMethod -Name GetUserByMail -Value {
            param($Mail, $AccessToken)
            # Try direct lookup first
            if ($this.Store.ContainsKey("mail:$Mail")) {
                return $this.Store["mail:$Mail"]
            }
            # Fallback to search (for backwards compatibility)
            foreach ($key in $this.Store.Keys) {
                if ($this.Store[$key].mail -eq $Mail) {
                    return $this.Store[$key]
                }
            }
            return $null
        }

        $fakeAdapter | Add-Member -MemberType ScriptMethod -Name CreateUser -Value {
            param($Payload, $AccessToken)
            $id = [guid]::NewGuid().ToString()
            $user = @{
                id                = $id
                userPrincipalName = $Payload.userPrincipalName
                mail              = $Payload.mail
                displayName       = $Payload.displayName
                accountEnabled    = $Payload.accountEnabled
                givenName         = $Payload.givenName
                surname           = $Payload.surname
            }
            $this.Store["id:$id"] = $user
            # Also store by UPN for easier lookup
            if ($Payload.userPrincipalName) {
                $this.Store["upn:$($Payload.userPrincipalName)"] = $user
            }
            return $user
        }

        $fakeAdapter | Add-Member -MemberType ScriptMethod -Name PatchUser -Value {
            param($ObjectId, $Payload, $AccessToken)
            $key = "id:$ObjectId"
            if ($this.Store.ContainsKey($key)) {
                foreach ($prop in $Payload.Keys) {
                    $this.Store[$key][$prop] = $Payload[$prop]
                }
            }
        }

        $fakeAdapter | Add-Member -MemberType ScriptMethod -Name DeleteUser -Value {
            param($ObjectId, $AccessToken)
            $key = "id:$ObjectId"
            if ($this.Store.ContainsKey($key)) {
                $this.Store.Remove($key)
            }
        }

        $fakeAdapter | Add-Member -MemberType ScriptMethod -Name ListUsers -Value {
            param($Filter, $AccessToken)
            $users = @()
            foreach ($key in $this.Store.Keys) {
                $users += $this.Store[$key]
            }
            return $users
        }

        $fakeAdapter | Add-Member -MemberType ScriptMethod -Name GetGroupById -Value {
            param($GroupId, $AccessToken)
            return @{
                id          = $GroupId
                displayName = "Group $GroupId"
                mail        = "group-$GroupId@test.local"
            }
        }

        $fakeAdapter | Add-Member -MemberType ScriptMethod -Name GetGroupByDisplayName -Value {
            param($DisplayName, $AccessToken)
            # Generate a deterministic GUID based on the display name
            # This simulates real Graph API behavior where groups have GUID ids
            $hash = [System.Security.Cryptography.SHA256]::Create().ComputeHash([System.Text.Encoding]::UTF8.GetBytes($DisplayName))
            $guidBytes = [byte[]]$hash[0..15]
            $guid = [System.Guid]::new($guidBytes)
            
            return @{
                id          = $guid.ToString()
                displayName = $DisplayName
                mail        = "group-$DisplayName@test.local"
            }
        }

        $fakeAdapter | Add-Member -MemberType ScriptMethod -Name ListUserGroups -Value {
            param($ObjectId, $AccessToken)
            $key = "groups:$ObjectId"
            if (-not $this.Store.ContainsKey($key)) {
                $this.Store[$key] = @()
            }
            return $this.Store[$key]
        }

        $fakeAdapter | Add-Member -MemberType ScriptMethod -Name AddGroupMember -Value {
            param($GroupObjectId, $UserObjectId, $AccessToken)
            $key = "groups:$UserObjectId"
            if (-not $this.Store.ContainsKey($key)) {
                $this.Store[$key] = @()
            }
            
            # Check if already a member (idempotency)
            $alreadyMember = $false
            foreach ($existingGroup in $this.Store[$key]) {
                if ($existingGroup.id -eq $GroupObjectId) {
                    $alreadyMember = $true
                    break
                }
            }
            
            if (-not $alreadyMember) {
                $group = @{
                    id          = $GroupObjectId
                    displayName = "Group $GroupObjectId"
                    mail        = "group-$GroupObjectId@test.local"
                }
                $this.Store[$key] += $group
            }
        }

        $fakeAdapter | Add-Member -MemberType ScriptMethod -Name RemoveGroupMember -Value {
            param($GroupObjectId, $UserObjectId, $AccessToken)
            $key = "groups:$UserObjectId"
            if ($this.Store.ContainsKey($key)) {
                $this.Store[$key] = $this.Store[$key] | Where-Object { $_.id -ne $GroupObjectId }
            }
        }

        $script:FakeAdapter = $fakeAdapter
    }

    Invoke-IdleIdentityProviderContractTests -NewProvider {
        New-IdleEntraIDIdentityProvider -Adapter $script:FakeAdapter
    }

    Invoke-IdleProviderCapabilitiesContractTests -ProviderFactory {
        New-IdleEntraIDIdentityProvider -Adapter $script:FakeAdapter
    }

    # Note: Generic entitlement contract tests are skipped for EntraID provider because:
    # - EntraID only supports Kind='Group' (not arbitrary entitlement kinds like 'Contract')
    # - Generic contract tests use Kind='Contract' which doesn't match EntraID's behavior
    # - EntraID-specific entitlement tests with Kind='Group' are in the 'EntraID identity provider - Entitlements' context below
}

Describe 'EntraID identity provider - Capabilities' {
    It 'Advertises expected capabilities by default' {
        $provider = New-IdleEntraIDIdentityProvider -Adapter ([pscustomobject]@{})
        $caps = $provider.GetCapabilities()

        $caps | Should -Contain 'IdLE.Identity.Read'
        $caps | Should -Contain 'IdLE.Identity.List'
        $caps | Should -Contain 'IdLE.Identity.Create'
        $caps | Should -Contain 'IdLE.Identity.Attribute.Ensure'
        $caps | Should -Contain 'IdLE.Identity.Disable'
        $caps | Should -Contain 'IdLE.Identity.Enable'
        $caps | Should -Contain 'IdLE.Identity.RevokeSessions'
        $caps | Should -Contain 'IdLE.Entitlement.List'
        $caps | Should -Contain 'IdLE.Entitlement.Grant'
        $caps | Should -Contain 'IdLE.Entitlement.Revoke'
        $caps | Should -Not -Contain 'IdLE.Identity.Delete'
    }

    It 'Advertises Delete capability when AllowDelete is true' {
        $provider = New-IdleEntraIDIdentityProvider -AllowDelete -Adapter ([pscustomobject]@{})
        $caps = $provider.GetCapabilities()

        $caps | Should -Contain 'IdLE.Identity.Delete'
    }

    It 'Does not advertise Delete capability when AllowDelete is false' {
        $provider = New-IdleEntraIDIdentityProvider -AllowDelete:$false -Adapter ([pscustomobject]@{})
        $caps = $provider.GetCapabilities()

        $caps | Should -Not -Contain 'IdLE.Identity.Delete'
    }
}

Describe 'EntraID identity provider - AllowDelete gate' {
    It 'Throws when Delete is called without AllowDelete' {
        $fakeAdapter = [pscustomobject]@{ PSTypeName = 'Fake' }
        $provider = New-IdleEntraIDIdentityProvider -Adapter $fakeAdapter

        { $provider.DeleteIdentity('test-id', 'fake-token') } | Should -Throw '*Delete capability is not enabled*'
    }

    It 'Allows Delete when AllowDelete is true' {
        $fakeAdapter = [pscustomobject]@{
            PSTypeName = 'Fake'
        }
        $fakeAdapter | Add-Member -MemberType ScriptMethod -Name GetUserById -Value {
            param($ObjectId, $AccessToken)
            return $null
        }

        $provider = New-IdleEntraIDIdentityProvider -AllowDelete -Adapter $fakeAdapter

        # Use GUID format, should not throw capability error
        $userId = [guid]::NewGuid().ToString()
        $result = $provider.DeleteIdentity($userId, 'fake-token')
        $result.Changed | Should -BeFalse
    }
}

Describe 'EntraID identity provider - Idempotency' {
    BeforeEach {
        $store = @{}
        $fakeAdapter = [pscustomobject]@{
            PSTypeName = 'IdLE.EntraIDAdapter.Fake'
            Store      = $store
        }

        $fakeAdapter | Add-Member -MemberType ScriptMethod -Name GetUserById -Value {
            param($ObjectId, $AccessToken)
            if ($this.Store.ContainsKey($ObjectId)) {
                return $this.Store[$ObjectId]
            }
            return $null
        }

        $fakeAdapter | Add-Member -MemberType ScriptMethod -Name GetUserByUpn -Value {
            param($Upn, $AccessToken)
            foreach ($key in $this.Store.Keys) {
                if ($this.Store[$key].userPrincipalName -eq $Upn) {
                    return $this.Store[$key]
                }
            }
            return $null
        }

        $fakeAdapter | Add-Member -MemberType ScriptMethod -Name GetUserByMail -Value {
            param($Mail, $AccessToken)
            foreach ($key in $this.Store.Keys) {
                if ($this.Store[$key].mail -eq $Mail) {
                    return $this.Store[$key]
                }
            }
            return $null
        }

        $fakeAdapter | Add-Member -MemberType ScriptMethod -Name CreateUser -Value {
            param($Payload, $AccessToken)
            $id = [guid]::NewGuid().ToString()
            $user = @{
                id             = $id
                userPrincipalName = $Payload.userPrincipalName
                displayName    = $Payload.displayName
                accountEnabled = $Payload.accountEnabled
            }
            $this.Store[$id] = $user
            return $user
        }

        $fakeAdapter | Add-Member -MemberType ScriptMethod -Name PatchUser -Value {
            param($ObjectId, $Payload, $AccessToken)
            if ($this.Store.ContainsKey($ObjectId)) {
                foreach ($prop in $Payload.Keys) {
                    $this.Store[$ObjectId][$prop] = $Payload[$prop]
                }
            }
        }

        $fakeAdapter | Add-Member -MemberType ScriptMethod -Name DeleteUser -Value {
            param($ObjectId, $AccessToken)
            if ($this.Store.ContainsKey($ObjectId)) {
                $this.Store.Remove($ObjectId)
            }
        }

        $script:TestAdapter = $fakeAdapter
    }

    It 'CreateIdentity is idempotent - returns Changed=false when user exists' {
        $provider = New-IdleEntraIDIdentityProvider -Adapter $script:TestAdapter

        $attrs = @{
            UserPrincipalName = 'test@test.local'
            DisplayName       = 'Test User'
        }

        $result1 = $provider.CreateIdentity('test@test.local', $attrs, 'fake-token')
        $result1.Changed | Should -BeTrue

        $userId = $result1.IdentityKey

        # Second create should be idempotent
        $result2 = $provider.CreateIdentity($userId, $attrs, 'fake-token')
        $result2.Changed | Should -BeFalse
    }

    It 'DeleteIdentity is idempotent - returns Changed=false when user does not exist' {
        $provider = New-IdleEntraIDIdentityProvider -AllowDelete -Adapter $script:TestAdapter

        $userId = [guid]::NewGuid().ToString()
        $result = $provider.DeleteIdentity($userId, 'fake-token')
        $result.Changed | Should -BeFalse
    }

    It 'DisableIdentity is idempotent - returns Changed=false when already disabled' {
        $provider = New-IdleEntraIDIdentityProvider -Adapter $script:TestAdapter

        $userId = [guid]::NewGuid().ToString()
        $script:TestAdapter.Store[$userId] = @{
            id             = $userId
            accountEnabled = $true
        }

        $result1 = $provider.DisableIdentity($userId, 'fake-token')
        $result1.Changed | Should -BeTrue

        $result2 = $provider.DisableIdentity($userId, 'fake-token')
        $result2.Changed | Should -BeFalse
    }

    It 'EnableIdentity is idempotent - returns Changed=false when already enabled' {
        $provider = New-IdleEntraIDIdentityProvider -Adapter $script:TestAdapter

        $userId = [guid]::NewGuid().ToString()
        $script:TestAdapter.Store[$userId] = @{
            id             = $userId
            accountEnabled = $false
        }

        $result1 = $provider.EnableIdentity($userId, 'fake-token')
        $result1.Changed | Should -BeTrue

        $result2 = $provider.EnableIdentity($userId, 'fake-token')
        $result2.Changed | Should -BeFalse
    }

    It 'EnsureAttribute is idempotent - returns Changed=false when value matches' {
        $provider = New-IdleEntraIDIdentityProvider -Adapter $script:TestAdapter

        $userId = [guid]::NewGuid().ToString()
        $script:TestAdapter.Store[$userId] = @{
            id          = $userId
            displayName = 'Old Name'
        }

        $result1 = $provider.EnsureAttribute($userId, 'DisplayName', 'New Name', 'fake-token')
        $result1.Changed | Should -BeTrue

        $result2 = $provider.EnsureAttribute($userId, 'DisplayName', 'New Name', 'fake-token')
        $result2.Changed | Should -BeFalse
    }
}

Describe 'EntraID identity provider - AuthSession handling' {
    BeforeEach {
        $fakeAdapter = [pscustomobject]@{
            PSTypeName    = 'IdLE.EntraIDAdapter.Fake'
            LastTokenUsed = $null
        }

        $fakeAdapter | Add-Member -MemberType ScriptMethod -Name GetUserById -Value {
            param($ObjectId, $AccessToken)
            $this.LastTokenUsed = $AccessToken
            return @{
                id             = $ObjectId
                accountEnabled = $true
                displayName    = "User $ObjectId"
            }
        }

        $script:TestAdapter = $fakeAdapter
    }

    It 'Accepts string access token' {
        $provider = New-IdleEntraIDIdentityProvider -Adapter $script:TestAdapter

        $userId = [guid]::NewGuid().ToString()
        $result = $provider.GetIdentity($userId, 'string-token')
        $script:TestAdapter.LastTokenUsed | Should -Be 'string-token'
    }

    It 'Accepts object with AccessToken property' {
        $provider = New-IdleEntraIDIdentityProvider -Adapter $script:TestAdapter

        $authSession = [pscustomobject]@{
            AccessToken = 'property-token'
        }

        $userId = [guid]::NewGuid().ToString()
        $result = $provider.GetIdentity($userId, $authSession)
        $script:TestAdapter.LastTokenUsed | Should -Be 'property-token'
    }

    It 'Accepts object with GetAccessToken() method' {
        $provider = New-IdleEntraIDIdentityProvider -Adapter $script:TestAdapter

        $authSession = [pscustomobject]@{}
        $authSession | Add-Member -MemberType ScriptMethod -Name GetAccessToken -Value {
            return 'method-token'
        }

        $userId = [guid]::NewGuid().ToString()
        $result = $provider.GetIdentity($userId, $authSession)
        $script:TestAdapter.LastTokenUsed | Should -Be 'method-token'
    }

    It 'Allows null AuthSession (for testing)' {
        $provider = New-IdleEntraIDIdentityProvider -Adapter $script:TestAdapter

        $userId = [guid]::NewGuid().ToString()
        # Should not throw - will use test token
        $provider.GetIdentity($userId, $null) | Should -Not -BeNullOrEmpty
    }

    It 'Throws when AuthSession format is unrecognized' {
        $provider = New-IdleEntraIDIdentityProvider -Adapter $script:TestAdapter

        $badSession = [pscustomobject]@{
            SomeProperty = 'value'
        }

        { $provider.GetIdentity('test-id', $badSession) } | Should -Throw '*AuthSession format not recognized*'
    }
}

Describe 'EntraID identity provider - Identity resolution' {
    BeforeEach {
        $store = @{}
        $fakeAdapter = [pscustomobject]@{
            PSTypeName = 'IdLE.EntraIDAdapter.Fake'
            Store      = $store
        }

        $fakeAdapter | Add-Member -MemberType ScriptMethod -Name GetUserById -Value {
            param($ObjectId, $AccessToken)
            if ($this.Store.ContainsKey("id:$ObjectId")) {
                return $this.Store["id:$ObjectId"]
            }
            return $null
        }

        $fakeAdapter | Add-Member -MemberType ScriptMethod -Name GetUserByUpn -Value {
            param($Upn, $AccessToken)
            if ($this.Store.ContainsKey("upn:$Upn")) {
                return $this.Store["upn:$Upn"]
            }
            return $null
        }

        $fakeAdapter | Add-Member -MemberType ScriptMethod -Name GetUserByMail -Value {
            param($Mail, $AccessToken)
            if ($this.Store.ContainsKey("mail:$Mail")) {
                return $this.Store["mail:$Mail"]
            }
            return $null
        }

        $script:TestAdapter = $fakeAdapter
    }

    It 'Resolves identity by objectId (GUID)' {
        $provider = New-IdleEntraIDIdentityProvider -Adapter $script:TestAdapter

        $guid = [guid]::NewGuid().ToString()
        $script:TestAdapter.Store["id:$guid"] = @{
            id             = $guid
            accountEnabled = $true
            displayName    = "User $guid"
        }

        $result = $provider.GetIdentity($guid, 'fake-token')
        $result.IdentityKey | Should -Be $guid
    }

    It 'Resolves identity by UPN' {
        $provider = New-IdleEntraIDIdentityProvider -Adapter $script:TestAdapter

        $upn = 'test@test.local'
        $userId = [guid]::NewGuid().ToString()
        $script:TestAdapter.Store["upn:$upn"] = @{
            id                = $userId
            userPrincipalName = $upn
            accountEnabled    = $true
            displayName       = "Test User"
        }

        $result = $provider.GetIdentity($upn, 'fake-token')
        $result.IdentityKey | Should -Be $upn  # Returns original key format
    }

    It 'Falls back to mail when UPN lookup fails' {
        $provider = New-IdleEntraIDIdentityProvider -Adapter $script:TestAdapter

        $mail = 'test@test.local'
        $userId = [guid]::NewGuid().ToString()
        $script:TestAdapter.Store["mail:$mail"] = @{
            id             = $userId
            mail           = $mail
            accountEnabled = $true
            displayName    = "Test User"
        }

        $result = $provider.GetIdentity($mail, 'fake-token')
        $result.IdentityKey | Should -Be $mail  # Returns original key format
    }

    It 'Throws when identity is not found' {
        $provider = New-IdleEntraIDIdentityProvider -Adapter $script:TestAdapter

        { $provider.GetIdentity('nonexistent@test.local', 'fake-token') } | Should -Throw '*not found*'
    }
}

Describe 'EntraID identity provider - Group resolution' {
    BeforeEach {
        $fakeAdapter = [pscustomobject]@{
            PSTypeName = 'IdLE.EntraIDAdapter.Fake'
        }

        $fakeAdapter | Add-Member -MemberType ScriptMethod -Name GetGroupById -Value {
            param($GroupId, $AccessToken)
            $guid = [System.Guid]::Empty
            if ([System.Guid]::TryParse($GroupId, [ref]$guid)) {
                return @{
                    id          = $GroupId
                    displayName = "Group $GroupId"
                }
            }
            return $null
        }

        $fakeAdapter | Add-Member -MemberType ScriptMethod -Name GetGroupByDisplayName -Value {
            param($DisplayName, $AccessToken)
            if ($DisplayName -eq 'AmbiguousGroup') {
                throw "Multiple groups found with displayName '$DisplayName'. Use objectId for deterministic lookup."
            }
            return @{
                id          = "resolved-$DisplayName"
                displayName = $DisplayName
            }
        }

        $script:TestAdapter = $fakeAdapter
    }

    It 'Resolves group by objectId' {
        $provider = New-IdleEntraIDIdentityProvider -Adapter $script:TestAdapter

        $groupGuid = [guid]::NewGuid().ToString()
        $resolvedId = $provider.NormalizeGroupId($groupGuid, 'fake-token')

        $resolvedId | Should -Be $groupGuid
    }

    It 'Resolves group by displayName' {
        $provider = New-IdleEntraIDIdentityProvider -Adapter $script:TestAdapter

        $resolvedId = $provider.NormalizeGroupId('UniqueGroup', 'fake-token')
        $resolvedId | Should -Be 'resolved-UniqueGroup'
    }

    It 'Throws when multiple groups match displayName' {
        $provider = New-IdleEntraIDIdentityProvider -Adapter $script:TestAdapter

        { $provider.NormalizeGroupId('AmbiguousGroup', 'fake-token') } | Should -Throw '*Multiple groups found*'
    }
}

Describe 'EntraID identity provider - Entitlement operations' {
    BeforeAll {
        function New-FakeEntraIDAdapterForEntitlements {
            $store = @{}

            $adapter = [pscustomobject]@{
                PSTypeName = 'IdLE.EntraIDAdapter.Fake'
                Store      = $store
            }

            $adapter | Add-Member -MemberType ScriptMethod -Name GetUserById -Value {
                param($ObjectId, $AccessToken)
                $key = "id:$ObjectId"
                if (-not $this.Store.ContainsKey($key)) {
                    $this.Store[$key] = @{
                        id                = $ObjectId
                        userPrincipalName = "$ObjectId@test.local"
                        displayName       = "User $ObjectId"
                        accountEnabled    = $true
                    }
                }
                return $this.Store[$key]
            }

            $adapter | Add-Member -MemberType ScriptMethod -Name GetGroupById -Value {
                param($GroupId, $AccessToken)
                return @{
                    id          = $GroupId
                    displayName = "Group $GroupId"
                    mail        = "group-$GroupId@test.local"
                }
            }

            $adapter | Add-Member -MemberType ScriptMethod -Name ListUserGroups -Value {
                param($ObjectId, $AccessToken)
                $key = "groups:$ObjectId"
                if (-not $this.Store.ContainsKey($key)) {
                    $this.Store[$key] = @()
                }
                return $this.Store[$key]
            }

            $adapter | Add-Member -MemberType ScriptMethod -Name AddGroupMember -Value {
                param($GroupObjectId, $UserObjectId, $AccessToken)
                $key = "groups:$UserObjectId"
                if (-not $this.Store.ContainsKey($key)) {
                    $this.Store[$key] = @()
                }

                $alreadyMember = $false
                foreach ($existingGroup in $this.Store[$key]) {
                    if ($existingGroup.id -eq $GroupObjectId) {
                        $alreadyMember = $true
                        break
                    }
                }

                if (-not $alreadyMember) {
                    $group = @{
                        id          = $GroupObjectId
                        displayName = "Group $GroupObjectId"
                        mail        = "group-$GroupObjectId@test.local"
                    }
                    $this.Store[$key] += $group
                }
            }

            $adapter | Add-Member -MemberType ScriptMethod -Name RemoveGroupMember -Value {
                param($GroupObjectId, $UserObjectId, $AccessToken)
                $key = "groups:$UserObjectId"
                if ($this.Store.ContainsKey($key)) {
                    $this.Store[$key] = @($this.Store[$key] | Where-Object { $_.id -ne $GroupObjectId })
                }
            }

            return $adapter
        }

        $script:EntAdapter = New-FakeEntraIDAdapterForEntitlements
        $script:EntProvider = New-IdleEntraIDIdentityProvider -Adapter $script:EntAdapter
    }

    It 'Exposes required entitlement methods' {
        $script:EntProvider.PSObject.Methods.Name | Should -Contain 'ListEntitlements'
        $script:EntProvider.PSObject.Methods.Name | Should -Contain 'GrantEntitlement'
        $script:EntProvider.PSObject.Methods.Name | Should -Contain 'RevokeEntitlement'
    }

    It 'GrantEntitlement returns stable result shape with Kind=Group' {
        $userId = [guid]::NewGuid().ToString()
        [void]$script:EntProvider.GetIdentity($userId)

        $entitlement = [pscustomobject]@{
            Kind = 'Group'
            Id   = [guid]::NewGuid().ToString()
        }

        $result = $script:EntProvider.GrantEntitlement($userId, $entitlement)

        $result | Should -Not -BeNullOrEmpty
        $result.PSObject.Properties.Name | Should -Contain 'Changed'
        $result.PSObject.Properties.Name | Should -Contain 'IdentityKey'
        $result.PSObject.Properties.Name | Should -Contain 'Entitlement'
        $result.Entitlement.Kind | Should -Be 'Group'
    }

    It 'GrantEntitlement is idempotent with Kind=Group' {
        $userId = [guid]::NewGuid().ToString()
        [void]$script:EntProvider.GetIdentity($userId)

        $entitlement = [pscustomobject]@{
            Kind = 'Group'
            Id   = [guid]::NewGuid().ToString()
        }

        $result1 = $script:EntProvider.GrantEntitlement($userId, $entitlement)
        $result1.Changed | Should -Be $true

        $result2 = $script:EntProvider.GrantEntitlement($userId, $entitlement)
        $result2.Changed | Should -Be $false
    }

    It 'RevokeEntitlement is idempotent (after a grant) with Kind=Group' {
        $userId = [guid]::NewGuid().ToString()
        [void]$script:EntProvider.GetIdentity($userId)

        $entitlement = [pscustomobject]@{
            Kind = 'Group'
            Id   = [guid]::NewGuid().ToString()
        }

        [void]$script:EntProvider.GrantEntitlement($userId, $entitlement)

        $result1 = $script:EntProvider.RevokeEntitlement($userId, $entitlement)
        $result1.Changed | Should -Be $true

        $result2 = $script:EntProvider.RevokeEntitlement($userId, $entitlement)
        $result2.Changed | Should -Be $false
    }

    It 'ListEntitlements reflects grant and revoke operations with Kind=Group' {
        $userId = [guid]::NewGuid().ToString()
        [void]$script:EntProvider.GetIdentity($userId)

        $entitlement = [pscustomobject]@{
            Kind = 'Group'
            Id   = [guid]::NewGuid().ToString()
        }

        $before = @($script:EntProvider.ListEntitlements($userId))

        [void]$script:EntProvider.GrantEntitlement($userId, $entitlement)
        $afterGrant = @($script:EntProvider.ListEntitlements($userId))

        [void]$script:EntProvider.RevokeEntitlement($userId, $entitlement)
        $afterRevoke = @($script:EntProvider.ListEntitlements($userId))

        @($afterGrant | Where-Object { $_.Kind -eq 'Group' -and $_.Id -eq $entitlement.Id }).Count | Should -Be 1
        @($afterRevoke | Where-Object { $_.Kind -eq 'Group' -and $_.Id -eq $entitlement.Id }).Count | Should -Be 0
    }
}

Describe 'EntraID identity provider - RevokeSessions' {
    BeforeAll {
        # Create a fake adapter that tracks revocation calls
        $fakeAdapter = [pscustomobject]@{
            PSTypeName          = 'IdLE.EntraIDAdapter.Fake'
            RevocationCallLog   = @()
            RevocationResponses = @{}
        }

        $fakeAdapter | Add-Member -MemberType ScriptMethod -Name GetUserById -Value {
            param($ObjectId, $AccessToken)
            return @{
                id                = $ObjectId
                userPrincipalName = "$ObjectId@test.local"
                accountEnabled    = $true
            }
        }

        $fakeAdapter | Add-Member -MemberType ScriptMethod -Name GetUserByUpn -Value {
            param($Upn, $AccessToken)
            return @{
                id                = 'test-user-id'
                userPrincipalName = $Upn
                accountEnabled    = $true
            }
        }

        $fakeAdapter | Add-Member -MemberType ScriptMethod -Name GetUserByMail -Value {
            param($Mail, $AccessToken)
            return @{
                id                = 'test-user-id'
                mail              = $Mail
                userPrincipalName = "$Mail"
                accountEnabled    = $true
            }
        }

        $fakeAdapter | Add-Member -MemberType ScriptMethod -Name RevokeSignInSessions -Value {
            param($ObjectId, $AccessToken)
            $this.RevocationCallLog += @{
                ObjectId    = $ObjectId
                AccessToken = $AccessToken
                Timestamp   = [datetime]::UtcNow
            }
            # Return a response that simulates Graph API behavior
            if ($this.RevocationResponses.ContainsKey($ObjectId)) {
                return $this.RevocationResponses[$ObjectId]
            }
            return [pscustomobject]@{
                '@odata.context' = 'https://graph.microsoft.com/v1.0/$metadata#Edm.Boolean'
                value            = $true
            }
        }

        $script:RevokeAdapter = $fakeAdapter
        $script:RevokeProvider = New-IdleEntraIDIdentityProvider -Adapter $script:RevokeAdapter
    }

    It 'Advertises IdLE.Identity.RevokeSessions capability' {
        $caps = $script:RevokeProvider.GetCapabilities()
        $caps | Should -Contain 'IdLE.Identity.RevokeSessions'
    }

    It 'Exposes RevokeSessions method' {
        $script:RevokeProvider.PSObject.Methods.Name | Should -Contain 'RevokeSessions'
    }

    It 'RevokeSessions calls adapter with correct user ID' {
        $userId = [guid]::NewGuid().ToString()
        $script:RevokeAdapter.RevocationCallLog = @()
        
        $result = $script:RevokeProvider.RevokeSessions($userId, 'fake-token')
        
        $script:RevokeAdapter.RevocationCallLog.Count | Should -Be 1
        $script:RevokeAdapter.RevocationCallLog[0].ObjectId | Should -Be $userId
    }

    It 'RevokeSessions returns ProviderResult with correct shape' {
        $userId = [guid]::NewGuid().ToString()
        
        $result = $script:RevokeProvider.RevokeSessions($userId, 'fake-token')
        
        $result | Should -Not -BeNullOrEmpty
        $result.PSObject.TypeNames[0] | Should -Be 'IdLE.ProviderResult'
        $result.Operation | Should -Be 'RevokeSessions'
        $result.IdentityKey | Should -Be $userId
        $result.PSObject.Properties.Name | Should -Contain 'Changed'
    }

    It 'RevokeSessions reports Changed=true when Graph returns value=true' {
        $userId = [guid]::NewGuid().ToString()
        $script:RevokeAdapter.RevocationResponses[$userId] = [pscustomobject]@{
            value = $true
        }
        
        $result = $script:RevokeProvider.RevokeSessions($userId, 'fake-token')
        
        $result.Changed | Should -Be $true
    }

    It 'RevokeSessions reports Changed=false when Graph returns value=false' {
        $userId = [guid]::NewGuid().ToString()
        $script:RevokeAdapter.RevocationResponses[$userId] = [pscustomobject]@{
            value = $false
        }
        
        $result = $script:RevokeProvider.RevokeSessions($userId, 'fake-token')
        
        $result.Changed | Should -Be $false
    }

    It 'RevokeSessions resolves identity by UPN' {
        $upn = 'test.user@contoso.com'
        $script:RevokeAdapter.RevocationCallLog = @()
        
        $result = $script:RevokeProvider.RevokeSessions($upn, 'fake-token')
        
        $script:RevokeAdapter.RevocationCallLog.Count | Should -Be 1
        $script:RevokeAdapter.RevocationCallLog[0].ObjectId | Should -Be 'test-user-id'
    }

    It 'RevokeSessions resolves identity by mail' {
        $mail = 'test.user@contoso.com'
        $script:RevokeAdapter.RevocationCallLog = @()
        
        $result = $script:RevokeProvider.RevokeSessions($mail, 'fake-token')
        
        $script:RevokeAdapter.RevocationCallLog.Count | Should -Be 1
        $script:RevokeAdapter.RevocationCallLog[0].ObjectId | Should -Be 'test-user-id'
    }

    It 'RevokeSessions accepts AuthSession object' {
        $userId = [guid]::NewGuid().ToString()
        $authSession = [pscustomobject]@{
            AccessToken = 'session-token'
        }
        
        $result = $script:RevokeProvider.RevokeSessions($userId, $authSession)
        
        $result | Should -Not -BeNullOrEmpty
        $result.Operation | Should -Be 'RevokeSessions'
    }
}

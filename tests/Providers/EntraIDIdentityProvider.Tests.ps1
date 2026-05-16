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
        # Create a mock adapter for contract tests
        $mockAdapter = [pscustomobject]@{
            PSTypeName = 'IdLE.EntraIDAdapter.Mock'
            Store      = @{}
        }

        $mockAdapter | Add-Member -MemberType ScriptMethod -Name GetUserById -Value {
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

        $mockAdapter | Add-Member -MemberType ScriptMethod -Name GetUserByUpn -Value {
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

        $mockAdapter | Add-Member -MemberType ScriptMethod -Name GetUserByMail -Value {
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

        $mockAdapter | Add-Member -MemberType ScriptMethod -Name CreateUser -Value {
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

        $mockAdapter | Add-Member -MemberType ScriptMethod -Name PatchUser -Value {
            param($ObjectId, $Payload, $AccessToken)
            $key = "id:$ObjectId"
            if ($this.Store.ContainsKey($key)) {
                foreach ($prop in $Payload.Keys) {
                    $this.Store[$key][$prop] = $Payload[$prop]
                }
            }
        }

        $mockAdapter | Add-Member -MemberType ScriptMethod -Name DeleteUser -Value {
            param($ObjectId, $AccessToken)
            $key = "id:$ObjectId"
            if ($this.Store.ContainsKey($key)) {
                $this.Store.Remove($key)
            }
        }

        $mockAdapter | Add-Member -MemberType ScriptMethod -Name ListUsers -Value {
            param($Filter, $AccessToken)
            $users = @()
            foreach ($key in $this.Store.Keys) {
                $users += $this.Store[$key]
            }
            return $users
        }

        $mockAdapter | Add-Member -MemberType ScriptMethod -Name GetGroupById -Value {
            param($GroupId, $AccessToken)
            return @{
                id          = $GroupId
                displayName = "Group $GroupId"
                mail        = "group-$GroupId@test.local"
            }
        }

        $mockAdapter | Add-Member -MemberType ScriptMethod -Name GetGroupByDisplayName -Value {
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

        $mockAdapter | Add-Member -MemberType ScriptMethod -Name ListUserGroups -Value {
            param($ObjectId, $AccessToken)
            $key = "groups:$ObjectId"
            if (-not $this.Store.ContainsKey($key)) {
                $this.Store[$key] = @()
            }
            return $this.Store[$key]
        }

        $mockAdapter | Add-Member -MemberType ScriptMethod -Name GetAdministrativeUnitById -Value {
            param($AuId, $AccessToken)
            return @{ id = $AuId; displayName = "AU $AuId" }
        }

        $mockAdapter | Add-Member -MemberType ScriptMethod -Name GetAdministrativeUnitByDisplayName -Value {
            param($DisplayName, $AccessToken)
            return @{ id = "resolved-au-$DisplayName"; displayName = $DisplayName }
        }

        $mockAdapter | Add-Member -MemberType ScriptMethod -Name ListUserAdministrativeUnits -Value {
            param($ObjectId, $AccessToken)
            $key = "aus:$ObjectId"
            if (-not $this.Store.ContainsKey($key)) {
                $this.Store[$key] = @()
            }
            return $this.Store[$key]
        }

        $mockAdapter | Add-Member -MemberType ScriptMethod -Name AddAdministrativeUnitMember -Value {
            param($AuObjectId, $UserObjectId, $AccessToken)
            $key = "aus:$UserObjectId"
            if (-not $this.Store.ContainsKey($key)) { $this.Store[$key] = @() }
            $alreadyMember = $null -ne ($this.Store[$key] | Where-Object { $_.id -eq $AuObjectId })
            if (-not $alreadyMember) {
                $this.Store[$key] += @{ id = $AuObjectId; displayName = "AU $AuObjectId" }
                return $true
            }
            return $false
        }

        $mockAdapter | Add-Member -MemberType ScriptMethod -Name RemoveAdministrativeUnitMember -Value {
            param($AuObjectId, $UserObjectId, $AccessToken)
            $key = "aus:$UserObjectId"
            if ($this.Store.ContainsKey($key)) {
                $wasMember = $null -ne ($this.Store[$key] | Where-Object { $_.id -eq $AuObjectId })
                $this.Store[$key] = @($this.Store[$key] | Where-Object { $_.id -ne $AuObjectId })
                return $wasMember
            }
            return $false
        }

        $mockAdapter | Add-Member -MemberType ScriptMethod -Name AddGroupMember -Value {
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
                return $true
            }
            return $false
        }

        $mockAdapter | Add-Member -MemberType ScriptMethod -Name RemoveGroupMember -Value {
            param($GroupObjectId, $UserObjectId, $AccessToken)
            $key = "groups:$UserObjectId"
            if ($this.Store.ContainsKey($key)) {
                $wasMember = $null -ne ($this.Store[$key] | Where-Object { $_.id -eq $GroupObjectId })
                $this.Store[$key] = @($this.Store[$key] | Where-Object { $_.id -ne $GroupObjectId })
                return $wasMember
            }
            return $false
        }

        $mockAdapter | Add-Member -MemberType ScriptMethod -Name BatchMembershipChanges -Value {
            param($Operations, $AccessToken)
            $results = @()
            foreach ($op in $Operations) {
                if ($op.Action -eq 'remove') {
                    $changed = [bool]$this.RemoveGroupMember($op.GroupObjectId, $op.UserObjectId, $AccessToken)
                } else {
                    $changed = [bool]$this.AddGroupMember($op.GroupObjectId, $op.UserObjectId, $AccessToken)
                }
                $results += [pscustomobject]@{
                    RequestId     = $op.RequestId
                    GroupObjectId = $op.GroupObjectId
                    Action        = $op.Action
                    Changed       = $changed
                    Error         = $null
                }
            }
            return $results
        }

        $script:MockAdapter = $mockAdapter
    }

    Context 'Contracts' {
        Invoke-IdleIdentityProviderContractTests -NewProvider {
            New-IdleEntraIDIdentityProvider -Adapter $script:MockAdapter
        }

        Invoke-IdleProviderCapabilitiesContractTests -ProviderFactory {
            New-IdleEntraIDIdentityProvider -Adapter $script:MockAdapter
        }

        # Note: Generic entitlement contract tests are skipped for EntraID provider because:
        # - EntraID only supports Kind='Group' (not arbitrary entitlement kinds like 'Contract')
        # - Generic contract tests use Kind='Contract' which doesn't match EntraID's behavior
        # - EntraID-specific entitlement tests with Kind='Group' are in the 'EntraID identity provider - Entitlements' context below
    }
}

Describe 'EntraID identity provider - Capabilities' {
    Context 'Capabilities' {
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
            $caps | Should -Contain 'IdLE.Entitlement.Prune'
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
}

Describe 'EntraID identity provider - AllowDelete gate' {
    Context 'Guard' {
        It 'Throws when Delete is called without AllowDelete' {
            $mockAdapter = [pscustomobject]@{ PSTypeName = 'Mock' }
            $provider = New-IdleEntraIDIdentityProvider -Adapter $mockAdapter

            { $provider.DeleteIdentity('test-id', 'mock-token') } | Should -Throw '*Delete capability is not enabled*'
        }

        It 'Allows Delete when AllowDelete is true' {
            $mockAdapter = [pscustomobject]@{
                PSTypeName = 'Mock'
            }
            $mockAdapter | Add-Member -MemberType ScriptMethod -Name GetUserById -Value {
                param($ObjectId, $AccessToken)
                return $null
            }

            $provider = New-IdleEntraIDIdentityProvider -AllowDelete -Adapter $mockAdapter

            # Use GUID format, should not throw capability error
            $userId = [guid]::NewGuid().ToString()
            $result = $provider.DeleteIdentity($userId, 'mock-token')
            $result.Changed | Should -BeFalse
        }
    }
}

Describe 'EntraID identity provider - Idempotency' {
    BeforeEach {
        $store = @{}
        $mockAdapter = [pscustomobject]@{
            PSTypeName = 'IdLE.EntraIDAdapter.Mock'
            Store      = $store
        }

        $mockAdapter | Add-Member -MemberType ScriptMethod -Name GetUserById -Value {
            param($ObjectId, $AccessToken)
            if ($this.Store.ContainsKey($ObjectId)) {
                return $this.Store[$ObjectId]
            }
            return $null
        }

        $mockAdapter | Add-Member -MemberType ScriptMethod -Name GetUserByUpn -Value {
            param($Upn, $AccessToken)
            foreach ($key in $this.Store.Keys) {
                if ($this.Store[$key].userPrincipalName -eq $Upn) {
                    return $this.Store[$key]
                }
            }
            return $null
        }

        $mockAdapter | Add-Member -MemberType ScriptMethod -Name GetUserByMail -Value {
            param($Mail, $AccessToken)
            foreach ($key in $this.Store.Keys) {
                if ($this.Store[$key].mail -eq $Mail) {
                    return $this.Store[$key]
                }
            }
            return $null
        }

        $mockAdapter | Add-Member -MemberType ScriptMethod -Name CreateUser -Value {
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

        $mockAdapter | Add-Member -MemberType ScriptMethod -Name PatchUser -Value {
            param($ObjectId, $Payload, $AccessToken)
            if ($this.Store.ContainsKey($ObjectId)) {
                foreach ($prop in $Payload.Keys) {
                    $this.Store[$ObjectId][$prop] = $Payload[$prop]
                }
            }
        }

        $mockAdapter | Add-Member -MemberType ScriptMethod -Name DeleteUser -Value {
            param($ObjectId, $AccessToken)
            if ($this.Store.ContainsKey($ObjectId)) {
                $this.Store.Remove($ObjectId)
            }
        }

        $script:TestAdapter = $mockAdapter
    }

    Context 'Idempotency' {
        It 'CreateIdentity is idempotent - returns Changed=false when user exists' {
            $provider = New-IdleEntraIDIdentityProvider -Adapter $script:TestAdapter

            $attrs = @{
                UserPrincipalName = 'test@test.local'
                DisplayName       = 'Test User'
            }

            $result1 = $provider.CreateIdentity('test@test.local', $attrs, 'mock-token')
            $result1.Changed | Should -BeTrue

            $userId = $result1.IdentityKey

            # Second create should be idempotent
            $result2 = $provider.CreateIdentity($userId, $attrs, 'mock-token')
            $result2.Changed | Should -BeFalse
        }

        It 'DeleteIdentity is idempotent - returns Changed=false when user does not exist' {
            $provider = New-IdleEntraIDIdentityProvider -AllowDelete -Adapter $script:TestAdapter

            $userId = [guid]::NewGuid().ToString()
            $result = $provider.DeleteIdentity($userId, 'mock-token')
            $result.Changed | Should -BeFalse
        }

        It 'DisableIdentity is idempotent - returns Changed=false when already disabled' {
            $provider = New-IdleEntraIDIdentityProvider -Adapter $script:TestAdapter

            $userId = [guid]::NewGuid().ToString()
            $script:TestAdapter.Store[$userId] = @{
                id             = $userId
                accountEnabled = $true
            }

            $result1 = $provider.DisableIdentity($userId, 'mock-token')
            $result1.Changed | Should -BeTrue

            $result2 = $provider.DisableIdentity($userId, 'mock-token')
            $result2.Changed | Should -BeFalse
        }

        It 'EnableIdentity is idempotent - returns Changed=false when already enabled' {
            $provider = New-IdleEntraIDIdentityProvider -Adapter $script:TestAdapter

            $userId = [guid]::NewGuid().ToString()
            $script:TestAdapter.Store[$userId] = @{
                id             = $userId
                accountEnabled = $false
            }

            $result1 = $provider.EnableIdentity($userId, 'mock-token')
            $result1.Changed | Should -BeTrue

            $result2 = $provider.EnableIdentity($userId, 'mock-token')
            $result2.Changed | Should -BeFalse
        }

        It 'EnsureAttribute is idempotent - returns Changed=false when value matches' {
            $provider = New-IdleEntraIDIdentityProvider -Adapter $script:TestAdapter

            $userId = [guid]::NewGuid().ToString()
            $script:TestAdapter.Store[$userId] = @{
                id          = $userId
                displayName = 'Old Name'
            }

            $result1 = $provider.EnsureAttribute($userId, 'DisplayName', 'New Name', 'mock-token')
            $result1.Changed | Should -BeTrue

            $result2 = $provider.EnsureAttribute($userId, 'DisplayName', 'New Name', 'mock-token')
            $result2.Changed | Should -BeFalse
        }
    }
}

Describe 'EntraID identity provider - AuthSession handling' {
    BeforeEach {
        $mockAdapter = [pscustomobject]@{
            PSTypeName    = 'IdLE.EntraIDAdapter.Mock'
            LastTokenUsed = $null
        }

        $mockAdapter | Add-Member -MemberType ScriptMethod -Name GetUserById -Value {
            param($ObjectId, $AccessToken)
            $this.LastTokenUsed = $AccessToken
            return @{
                id             = $ObjectId
                accountEnabled = $true
                displayName    = "User $ObjectId"
            }
        }

        $script:TestAdapter = $mockAdapter
    }

    Context 'AuthSession formats' {
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
}

Describe 'EntraID identity provider - Identity resolution' {
    BeforeEach {
        $store = @{}
        $mockAdapter = [pscustomobject]@{
            PSTypeName = 'IdLE.EntraIDAdapter.Mock'
            Store      = $store
        }

        $mockAdapter | Add-Member -MemberType ScriptMethod -Name GetUserById -Value {
            param($ObjectId, $AccessToken)
            if ($this.Store.ContainsKey("id:$ObjectId")) {
                return $this.Store["id:$ObjectId"]
            }
            return $null
        }

        $mockAdapter | Add-Member -MemberType ScriptMethod -Name GetUserByUpn -Value {
            param($Upn, $AccessToken)
            if ($this.Store.ContainsKey("upn:$Upn")) {
                return $this.Store["upn:$Upn"]
            }
            return $null
        }

        $mockAdapter | Add-Member -MemberType ScriptMethod -Name GetUserByMail -Value {
            param($Mail, $AccessToken)
            if ($this.Store.ContainsKey("mail:$Mail")) {
                return $this.Store["mail:$Mail"]
            }
            return $null
        }

        $script:TestAdapter = $mockAdapter
    }

    Context 'Lookups' {
        It 'Resolves identity by objectId (GUID)' {
            $provider = New-IdleEntraIDIdentityProvider -Adapter $script:TestAdapter

            $guid = [guid]::NewGuid().ToString()
            $script:TestAdapter.Store["id:$guid"] = @{
                id             = $guid
                accountEnabled = $true
                displayName    = "User $guid"
            }

            $result = $provider.GetIdentity($guid, 'mock-token')
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

            $result = $provider.GetIdentity($upn, 'mock-token')
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

            $result = $provider.GetIdentity($mail, 'mock-token')
            $result.IdentityKey | Should -Be $mail  # Returns original key format
        }

        It 'Throws when identity is not found' {
            $provider = New-IdleEntraIDIdentityProvider -Adapter $script:TestAdapter

            { $provider.GetIdentity('nonexistent@test.local', 'mock-token') } | Should -Throw '*not found*'
        }
    }
}

Describe 'EntraID identity provider - Group resolution' {
    BeforeEach {
        $mockAdapter = [pscustomobject]@{
            PSTypeName = 'IdLE.EntraIDAdapter.Mock'
        }

        $mockAdapter | Add-Member -MemberType ScriptMethod -Name GetGroupById -Value {
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

        $mockAdapter | Add-Member -MemberType ScriptMethod -Name GetGroupByDisplayName -Value {
            param($DisplayName, $AccessToken)
            if ($DisplayName -eq 'AmbiguousGroup') {
                throw "Multiple groups found with displayName '$DisplayName'. Use objectId for deterministic lookup."
            }
            return @{
                id          = "resolved-$DisplayName"
                displayName = $DisplayName
            }
        }

        $script:TestAdapter = $mockAdapter
    }

    Context 'Lookups' {
        It 'Resolves group by objectId' {
            $provider = New-IdleEntraIDIdentityProvider -Adapter $script:TestAdapter

            $groupGuid = [guid]::NewGuid().ToString()
            $resolvedId = $provider.ResolveGroup($groupGuid, 'mock-token')

            $resolvedId | Should -Be $groupGuid
        }

        It 'Resolves group by displayName' {
            $provider = New-IdleEntraIDIdentityProvider -Adapter $script:TestAdapter

            $resolvedId = $provider.ResolveGroup('UniqueGroup', 'mock-token')
            $resolvedId | Should -Be 'resolved-UniqueGroup'
        }

        It 'Throws when multiple groups match displayName' {
            $provider = New-IdleEntraIDIdentityProvider -Adapter $script:TestAdapter

            { $provider.ResolveGroup('AmbiguousGroup', 'mock-token') } | Should -Throw '*Multiple groups found*'
        }
    }
}

Describe 'EntraID identity provider - Administrative Unit resolution' {
    BeforeEach {
        $mockAdapter = [pscustomobject]@{
            PSTypeName = 'IdLE.EntraIDAdapter.Mock'
        }

        $mockAdapter | Add-Member -MemberType ScriptMethod -Name GetAdministrativeUnitById -Value {
            param($AuId, $AccessToken)
            $guid = [System.Guid]::Empty
            if ([System.Guid]::TryParse($AuId, [ref]$guid)) {
                return @{ id = $AuId; displayName = "AU $AuId" }
            }
            return $null
        }

        $mockAdapter | Add-Member -MemberType ScriptMethod -Name GetAdministrativeUnitByDisplayName -Value {
            param($DisplayName, $AccessToken)
            if ($DisplayName -eq 'AmbiguousAU') {
                throw "Multiple Administrative Units found with displayName '$DisplayName'. Use objectId for deterministic lookup."
            }
            if ($DisplayName -eq 'MissingAU') {
                return $null
            }
            return @{ id = "resolved-au-$DisplayName"; displayName = $DisplayName }
        }

        $script:AuTestAdapter = $mockAdapter
    }

    Context 'Lookups' {
        It 'Resolves Administrative Unit by objectId' {
            $provider = New-IdleEntraIDIdentityProvider -Adapter $script:AuTestAdapter

            $auGuid = [guid]::NewGuid().ToString()
            $resolvedId = $provider.ResolveAdministrativeUnit($auGuid, 'mock-token')

            $resolvedId | Should -Be $auGuid
        }

        It 'Resolves Administrative Unit by displayName' {
            $provider = New-IdleEntraIDIdentityProvider -Adapter $script:AuTestAdapter

            $resolvedId = $provider.ResolveAdministrativeUnit('EU Region Admins', 'mock-token')
            $resolvedId | Should -Be 'resolved-au-EU Region Admins'
        }

        It 'Throws when GUID objectId is not found' {
            $provider = New-IdleEntraIDIdentityProvider -Adapter $script:AuTestAdapter

            $missingGuid = [guid]::NewGuid().ToString()
            # Override GetAdministrativeUnitById to return null for this GUID
            $script:AuTestAdapter | Add-Member -MemberType ScriptMethod -Name GetAdministrativeUnitById -Value {
                param($AuId, $AccessToken)
                return $null
            } -Force

            { $provider.ResolveAdministrativeUnit($missingGuid, 'mock-token') } | Should -Throw '*not found*'
        }

        It 'Throws when displayName is not found' {
            $provider = New-IdleEntraIDIdentityProvider -Adapter $script:AuTestAdapter

            { $provider.ResolveAdministrativeUnit('MissingAU', 'mock-token') } | Should -Throw '*not found*'
        }

        It 'Throws when multiple Administrative Units match displayName' {
            $provider = New-IdleEntraIDIdentityProvider -Adapter $script:AuTestAdapter

            { $provider.ResolveAdministrativeUnit('AmbiguousAU', 'mock-token') } | Should -Throw '*Multiple Administrative Units found*'
        }
    }
}

Describe 'EntraID identity provider - Entitlement operations' {
    BeforeAll {
        function New-MockEntraIDAdapterForEntitlements {
            $store = @{}

            $adapter = [pscustomobject]@{
                PSTypeName = 'IdLE.EntraIDAdapter.Mock'
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

            $adapter | Add-Member -MemberType ScriptMethod -Name GetAdministrativeUnitById -Value {
                param($AuId, $AccessToken)
                return @{ id = $AuId; displayName = "AU $AuId" }
            }

            $adapter | Add-Member -MemberType ScriptMethod -Name GetAdministrativeUnitByDisplayName -Value {
                param($DisplayName, $AccessToken)
                return @{ id = "resolved-au-$DisplayName"; displayName = $DisplayName }
            }

            $adapter | Add-Member -MemberType ScriptMethod -Name ListUserAdministrativeUnits -Value {
                param($ObjectId, $AccessToken)
                $key = "aus:$ObjectId"
                if (-not $this.Store.ContainsKey($key)) {
                    $this.Store[$key] = @()
                }
                return $this.Store[$key]
            }

            $adapter | Add-Member -MemberType ScriptMethod -Name AddAdministrativeUnitMember -Value {
                param($AuObjectId, $UserObjectId, $AccessToken)
                $key = "aus:$UserObjectId"
                if (-not $this.Store.ContainsKey($key)) { $this.Store[$key] = @() }
                $alreadyMember = $null -ne ($this.Store[$key] | Where-Object { $_.id -eq $AuObjectId })
                if (-not $alreadyMember) {
                    $this.Store[$key] += @{ id = $AuObjectId; displayName = "AU $AuObjectId" }
                    return $true
                }
                return $false
            }

            $adapter | Add-Member -MemberType ScriptMethod -Name RemoveAdministrativeUnitMember -Value {
                param($AuObjectId, $UserObjectId, $AccessToken)
                $key = "aus:$UserObjectId"
                if ($this.Store.ContainsKey($key)) {
                    $wasMember = $null -ne ($this.Store[$key] | Where-Object { $_.id -eq $AuObjectId })
                    $this.Store[$key] = @($this.Store[$key] | Where-Object { $_.id -ne $AuObjectId })
                    return $wasMember
                }
                return $false
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
                    return $true
                }
                return $false
            }

            $adapter | Add-Member -MemberType ScriptMethod -Name RemoveGroupMember -Value {
                param($GroupObjectId, $UserObjectId, $AccessToken)
                $key = "groups:$UserObjectId"
                if ($this.Store.ContainsKey($key)) {
                    $wasMember = $null -ne ($this.Store[$key] | Where-Object { $_.id -eq $GroupObjectId })
                    $this.Store[$key] = @($this.Store[$key] | Where-Object { $_.id -ne $GroupObjectId })
                    return $wasMember
                }
                return $false
            }

            $adapter | Add-Member -MemberType ScriptMethod -Name BatchMembershipChanges -Value {
                param($Operations, $AccessToken)
                $results = @()
                foreach ($op in $Operations) {
                    if ($op.Action -eq 'remove') {
                        $changed = [bool]$this.RemoveGroupMember($op.GroupObjectId, $op.UserObjectId, $AccessToken)
                    } else {
                        $changed = [bool]$this.AddGroupMember($op.GroupObjectId, $op.UserObjectId, $AccessToken)
                    }
                    $results += [pscustomobject]@{
                        RequestId     = $op.RequestId
                        GroupObjectId = $op.GroupObjectId
                        Action        = $op.Action
                        Changed       = $changed
                        Error         = $null
                    }
                }
                return $results
            }

            return $adapter
        }

        $script:EntAdapter = New-MockEntraIDAdapterForEntitlements
        $script:EntProvider = New-IdleEntraIDIdentityProvider -Adapter $script:EntAdapter
    }

    Context 'Operations' {
        It 'Exposes required entitlement methods' {
            $script:EntProvider.PSObject.Methods.Name | Should -Contain 'ListEntitlements'
            $script:EntProvider.PSObject.Methods.Name | Should -Contain 'GrantEntitlement'
            $script:EntProvider.PSObject.Methods.Name | Should -Contain 'RevokeEntitlement'
            $script:EntProvider.PSObject.Methods.Name | Should -Contain 'BulkRevokeEntitlements'
            $script:EntProvider.PSObject.Methods.Name | Should -Contain 'BulkGrantEntitlements'
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

        It 'BulkRevokeEntitlements removes multiple groups and returns per-item Changed' {
            $userId = [guid]::NewGuid().ToString()
            [void]$script:EntProvider.GetIdentity($userId)

            $g1 = [guid]::NewGuid().ToString()
            $g2 = [guid]::NewGuid().ToString()
            [void]$script:EntProvider.GrantEntitlement($userId, @{ Kind = 'Group'; Id = $g1 })
            [void]$script:EntProvider.GrantEntitlement($userId, @{ Kind = 'Group'; Id = $g2 })

            $results = $script:EntProvider.BulkRevokeEntitlements($userId, @(
                @{ Kind = 'Group'; Id = $g1 },
                @{ Kind = 'Group'; Id = $g2 }
            ))

            @($results).Count | Should -Be 2
            ($results | Where-Object { $_.Changed -eq $true }).Count | Should -Be 2
            @($results | Where-Object { $null -ne $_.Error }).Count | Should -Be 0

            @($script:EntProvider.ListEntitlements($userId) | Where-Object { $_.Id -eq $g1 }).Count | Should -Be 0
            @($script:EntProvider.ListEntitlements($userId) | Where-Object { $_.Id -eq $g2 }).Count | Should -Be 0
        }

        It 'BulkRevokeEntitlements is idempotent (not a member → Changed=$false)' {
            $userId = [guid]::NewGuid().ToString()
            [void]$script:EntProvider.GetIdentity($userId)

            $g1 = [guid]::NewGuid().ToString()

            $results = $script:EntProvider.BulkRevokeEntitlements($userId, @(
                @{ Kind = 'Group'; Id = $g1 }
            ))

            @($results).Count | Should -Be 1
            $results[0].Changed | Should -Be $false
            $results[0].Error | Should -BeNullOrEmpty
        }

        It 'BulkGrantEntitlements adds multiple groups and returns per-item Changed' {
            $userId = [guid]::NewGuid().ToString()
            [void]$script:EntProvider.GetIdentity($userId)

            $g1 = [guid]::NewGuid().ToString()
            $g2 = [guid]::NewGuid().ToString()

            $results = $script:EntProvider.BulkGrantEntitlements($userId, @(
                @{ Kind = 'Group'; Id = $g1 },
                @{ Kind = 'Group'; Id = $g2 }
            ))

            @($results).Count | Should -Be 2
            ($results | Where-Object { $_.Changed -eq $true }).Count | Should -Be 2
            @($results | Where-Object { $null -ne $_.Error }).Count | Should -Be 0

            @($script:EntProvider.ListEntitlements($userId) | Where-Object { $_.Id -eq $g1 }).Count | Should -Be 1
            @($script:EntProvider.ListEntitlements($userId) | Where-Object { $_.Id -eq $g2 }).Count | Should -Be 1
        }

        It 'BulkGrantEntitlements is idempotent (already a member → Changed=$false)' {
            $userId = [guid]::NewGuid().ToString()
            [void]$script:EntProvider.GetIdentity($userId)

            $g1 = [guid]::NewGuid().ToString()
            [void]$script:EntProvider.GrantEntitlement($userId, @{ Kind = 'Group'; Id = $g1 })

            $results = $script:EntProvider.BulkGrantEntitlements($userId, @(
                @{ Kind = 'Group'; Id = $g1 }
            ))

            @($results).Count | Should -Be 1
            $results[0].Changed | Should -Be $false
            $results[0].Error | Should -BeNullOrEmpty
        }

        It 'BulkGrantEntitlements adds an AdministrativeUnit membership and returns Changed=$true' {
            $userId = [guid]::NewGuid().ToString()
            [void]$script:EntProvider.GetIdentity($userId)
            $auId = [guid]::NewGuid().ToString()

            $results = $script:EntProvider.BulkGrantEntitlements($userId, @(
                @{ Kind = 'AdministrativeUnit'; Id = $auId }
            ))

            @($results).Count | Should -Be 1
            $results[0].Changed | Should -Be $true
            $results[0].Error | Should -BeNullOrEmpty
            $results[0].Entitlement.Kind | Should -Be 'AdministrativeUnit'

            @($script:EntProvider.ListEntitlements($userId) | Where-Object { $_.Kind -eq 'AdministrativeUnit' -and $_.Id -eq $auId }).Count | Should -Be 1
        }

        It 'BulkGrantEntitlements is idempotent for AdministrativeUnit (already a member → Changed=$false)' {
            $userId = [guid]::NewGuid().ToString()
            [void]$script:EntProvider.GetIdentity($userId)
            $auId = [guid]::NewGuid().ToString()
            [void]$script:EntProvider.GrantEntitlement($userId, @{ Kind = 'AdministrativeUnit'; Id = $auId })

            $results = $script:EntProvider.BulkGrantEntitlements($userId, @(
                @{ Kind = 'AdministrativeUnit'; Id = $auId }
            ))

            @($results).Count | Should -Be 1
            $results[0].Changed | Should -Be $false
            $results[0].Error | Should -BeNullOrEmpty
        }

        It 'BulkGrantEntitlements handles mixed Group and AdministrativeUnit in a single call' {
            $userId  = [guid]::NewGuid().ToString()
            [void]$script:EntProvider.GetIdentity($userId)
            $groupId = [guid]::NewGuid().ToString()
            $auId    = [guid]::NewGuid().ToString()

            $results = $script:EntProvider.BulkGrantEntitlements($userId, @(
                @{ Kind = 'Group';               Id = $groupId },
                @{ Kind = 'AdministrativeUnit'; Id = $auId    }
            ))

            @($results).Count | Should -Be 2
            ($results | Where-Object { $_.Changed -eq $true }).Count | Should -Be 2

            @($script:EntProvider.ListEntitlements($userId) | Where-Object { $_.Kind -eq 'Group'               -and $_.Id -eq $groupId }).Count | Should -Be 1
            @($script:EntProvider.ListEntitlements($userId) | Where-Object { $_.Kind -eq 'AdministrativeUnit' -and $_.Id -eq $auId    }).Count | Should -Be 1
        }

        It 'BulkRevokeEntitlements removes an AdministrativeUnit membership and returns Changed=$true' {
            $userId = [guid]::NewGuid().ToString()
            [void]$script:EntProvider.GetIdentity($userId)
            $auId = [guid]::NewGuid().ToString()
            [void]$script:EntProvider.GrantEntitlement($userId, @{ Kind = 'AdministrativeUnit'; Id = $auId })

            $results = $script:EntProvider.BulkRevokeEntitlements($userId, @(
                @{ Kind = 'AdministrativeUnit'; Id = $auId }
            ))

            @($results).Count | Should -Be 1
            $results[0].Changed | Should -Be $true
            $results[0].Error | Should -BeNullOrEmpty
            $results[0].Entitlement.Kind | Should -Be 'AdministrativeUnit'

            @($script:EntProvider.ListEntitlements($userId) | Where-Object { $_.Kind -eq 'AdministrativeUnit' -and $_.Id -eq $auId }).Count | Should -Be 0
        }

        It 'BulkRevokeEntitlements is idempotent for AdministrativeUnit (not a member → Changed=$false)' {
            $userId = [guid]::NewGuid().ToString()
            [void]$script:EntProvider.GetIdentity($userId)
            $auId = [guid]::NewGuid().ToString()

            $results = $script:EntProvider.BulkRevokeEntitlements($userId, @(
                @{ Kind = 'AdministrativeUnit'; Id = $auId }
            ))

            @($results).Count | Should -Be 1
            $results[0].Changed | Should -Be $false
            $results[0].Error | Should -BeNullOrEmpty
        }

        It 'BulkRevokeEntitlements handles mixed Group and AdministrativeUnit in a single call' {
            $userId = [guid]::NewGuid().ToString()
            [void]$script:EntProvider.GetIdentity($userId)
            $groupId = [guid]::NewGuid().ToString()
            $auId    = [guid]::NewGuid().ToString()
            [void]$script:EntProvider.GrantEntitlement($userId, @{ Kind = 'Group';               Id = $groupId })
            [void]$script:EntProvider.GrantEntitlement($userId, @{ Kind = 'AdministrativeUnit'; Id = $auId    })

            $results = $script:EntProvider.BulkRevokeEntitlements($userId, @(
                @{ Kind = 'Group';               Id = $groupId },
                @{ Kind = 'AdministrativeUnit'; Id = $auId    }
            ))

            @($results).Count | Should -Be 2
            ($results | Where-Object { $_.Changed -eq $true }).Count | Should -Be 2

            @($script:EntProvider.ListEntitlements($userId) | Where-Object { $_.Kind -eq 'Group' -and $_.Id -eq $groupId }).Count | Should -Be 0
            @($script:EntProvider.ListEntitlements($userId) | Where-Object { $_.Kind -eq 'AdministrativeUnit' -and $_.Id -eq $auId }).Count | Should -Be 0
        }

        It 'GrantEntitlement returns stable result shape with Kind=AdministrativeUnit' {
            $userId = [guid]::NewGuid().ToString()
            [void]$script:EntProvider.GetIdentity($userId)
            $auId = [guid]::NewGuid().ToString()

            $result = $script:EntProvider.GrantEntitlement($userId, @{ Kind = 'AdministrativeUnit'; Id = $auId })

            $result.Operation | Should -Be 'GrantEntitlement'
            $result.Changed | Should -Be $true
            $result.Entitlement.Kind | Should -Be 'AdministrativeUnit'
            $result.Entitlement.Id | Should -Be $auId
        }

        It 'GrantEntitlement is idempotent with Kind=AdministrativeUnit' {
            $userId = [guid]::NewGuid().ToString()
            [void]$script:EntProvider.GetIdentity($userId)
            $auId = [guid]::NewGuid().ToString()

            $result1 = $script:EntProvider.GrantEntitlement($userId, @{ Kind = 'AdministrativeUnit'; Id = $auId })
            $result2 = $script:EntProvider.GrantEntitlement($userId, @{ Kind = 'AdministrativeUnit'; Id = $auId })

            $result1.Changed | Should -Be $true
            $result2.Changed | Should -Be $false
        }

        It 'RevokeEntitlement is idempotent with Kind=AdministrativeUnit' {
            $userId = [guid]::NewGuid().ToString()
            [void]$script:EntProvider.GetIdentity($userId)
            $auId = [guid]::NewGuid().ToString()

            [void]$script:EntProvider.GrantEntitlement($userId, @{ Kind = 'AdministrativeUnit'; Id = $auId })

            $result1 = $script:EntProvider.RevokeEntitlement($userId, @{ Kind = 'AdministrativeUnit'; Id = $auId })
            $result2 = $script:EntProvider.RevokeEntitlement($userId, @{ Kind = 'AdministrativeUnit'; Id = $auId })

            $result1.Changed | Should -Be $true
            $result2.Changed | Should -Be $false
        }

        It 'ListEntitlements reflects AdministrativeUnit grant and revoke' {
            $userId = [guid]::NewGuid().ToString()
            [void]$script:EntProvider.GetIdentity($userId)
            $auId = [guid]::NewGuid().ToString()

            $before = @($script:EntProvider.ListEntitlements($userId))

            [void]$script:EntProvider.GrantEntitlement($userId, @{ Kind = 'AdministrativeUnit'; Id = $auId })
            $afterGrant = @($script:EntProvider.ListEntitlements($userId))

            [void]$script:EntProvider.RevokeEntitlement($userId, @{ Kind = 'AdministrativeUnit'; Id = $auId })
            $afterRevoke = @($script:EntProvider.ListEntitlements($userId))

            @($afterGrant | Where-Object { $_.Kind -eq 'AdministrativeUnit' -and $_.Id -eq $auId }).Count | Should -Be 1
            @($afterRevoke | Where-Object { $_.Kind -eq 'AdministrativeUnit' -and $_.Id -eq $auId }).Count | Should -Be 0
        }

        It 'ListEntitlements returns both Group and AdministrativeUnit entitlements' {
            $userId = [guid]::NewGuid().ToString()
            [void]$script:EntProvider.GetIdentity($userId)
            $groupId = [guid]::NewGuid().ToString()
            $auId = [guid]::NewGuid().ToString()

            [void]$script:EntProvider.GrantEntitlement($userId, @{ Kind = 'Group'; Id = $groupId })
            [void]$script:EntProvider.GrantEntitlement($userId, @{ Kind = 'AdministrativeUnit'; Id = $auId })

            $entitlements = @($script:EntProvider.ListEntitlements($userId))

            @($entitlements | Where-Object { $_.Kind -eq 'Group' -and $_.Id -eq $groupId }).Count | Should -Be 1
            @($entitlements | Where-Object { $_.Kind -eq 'AdministrativeUnit' -and $_.Id -eq $auId }).Count | Should -Be 1
        }

        It 'GrantEntitlement throws for unsupported Kind' {
            $userId = [guid]::NewGuid().ToString()
            [void]$script:EntProvider.GetIdentity($userId)

            { $script:EntProvider.GrantEntitlement($userId, @{ Kind = 'Unknown'; Id = [guid]::NewGuid().ToString() }) } |
                Should -Throw "*Kind 'Group' or 'AdministrativeUnit'*"
        }

        It 'RevokeEntitlement throws for unsupported Kind' {
            $userId = [guid]::NewGuid().ToString()
            [void]$script:EntProvider.GetIdentity($userId)

            { $script:EntProvider.RevokeEntitlement($userId, @{ Kind = 'Unknown'; Id = [guid]::NewGuid().ToString() }) } |
                Should -Throw "*Kind 'Group' or 'AdministrativeUnit'*"
        }
    }
}

Describe 'EntraID identity provider - RevokeSessions' {
    BeforeAll {
        # Create a mock adapter that tracks revocation calls
        $mockAdapter = [pscustomobject]@{
            PSTypeName          = 'IdLE.EntraIDAdapter.Mock'
            RevocationCallLog   = @()
            RevocationResponses = @{}
        }

        $mockAdapter | Add-Member -MemberType ScriptMethod -Name GetUserById -Value {
            param($ObjectId, $AccessToken)
            return @{
                id                = $ObjectId
                userPrincipalName = "$ObjectId@test.local"
                accountEnabled    = $true
            }
        }

        $mockAdapter | Add-Member -MemberType ScriptMethod -Name GetUserByUpn -Value {
            param($Upn, $AccessToken)
            return @{
                id                = 'test-user-id'
                userPrincipalName = $Upn
                accountEnabled    = $true
            }
        }

        $mockAdapter | Add-Member -MemberType ScriptMethod -Name GetUserByMail -Value {
            param($Mail, $AccessToken)
            return @{
                id                = 'test-user-id'
                mail              = $Mail
                userPrincipalName = "$Mail"
                accountEnabled    = $true
            }
        }

        $mockAdapter | Add-Member -MemberType ScriptMethod -Name RevokeSignInSessions -Value {
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

        $script:RevokeAdapter = $mockAdapter
        $script:RevokeProvider = New-IdleEntraIDIdentityProvider -Adapter $script:RevokeAdapter
    }

    Context 'Operations' {
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
            
            $result = $script:RevokeProvider.RevokeSessions($userId, 'mock-token')
            
            $script:RevokeAdapter.RevocationCallLog.Count | Should -Be 1
            $script:RevokeAdapter.RevocationCallLog[0].ObjectId | Should -Be $userId
        }

        It 'RevokeSessions returns ProviderResult with correct shape' {
            $userId = [guid]::NewGuid().ToString()
            
            $result = $script:RevokeProvider.RevokeSessions($userId, 'mock-token')
            
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
            
            $result = $script:RevokeProvider.RevokeSessions($userId, 'mock-token')
            
            $result.Changed | Should -Be $true
        }

        It 'RevokeSessions reports Changed=false when Graph returns value=false' {
            $userId = [guid]::NewGuid().ToString()
            $script:RevokeAdapter.RevocationResponses[$userId] = [pscustomobject]@{
                value = $false
            }
            
            $result = $script:RevokeProvider.RevokeSessions($userId, 'mock-token')
            
            $result.Changed | Should -Be $false
        }

        It 'RevokeSessions resolves identity by UPN' {
            $upn = 'test.user@contoso.com'
            $script:RevokeAdapter.RevocationCallLog = @()
            
            $result = $script:RevokeProvider.RevokeSessions($upn, 'mock-token')
            
            $script:RevokeAdapter.RevocationCallLog.Count | Should -Be 1
            $script:RevokeAdapter.RevocationCallLog[0].ObjectId | Should -Be 'test-user-id'
        }

        It 'RevokeSessions resolves identity by mail' {
            $mail = 'test.user@contoso.com'
            $script:RevokeAdapter.RevocationCallLog = @()
            
            $result = $script:RevokeProvider.RevokeSessions($mail, 'mock-token')
            
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
}

Describe 'EntraID identity provider - Password generation' {
    BeforeAll {
        # Create a mock adapter for password generation tests
        $mockAdapter = [pscustomobject]@{
            PSTypeName = 'IdLE.EntraIDAdapter.Mock'
            Store      = @{}
            LastCreatePayload = $null
        }

        $mockAdapter | Add-Member -MemberType ScriptMethod -Name GetUserById -Value {
            param($ObjectId, $AccessToken)
            return $null
        }

        $mockAdapter | Add-Member -MemberType ScriptMethod -Name GetUserByUpn -Value {
            param($Upn, $AccessToken)
            return $null
        }

        $mockAdapter | Add-Member -MemberType ScriptMethod -Name GetUserByMail -Value {
            param($Mail, $AccessToken)
            return $null
        }

        $mockAdapter | Add-Member -MemberType ScriptMethod -Name CreateUser -Value {
            param($Payload, $AccessToken)
            
            # Store the payload for inspection
            $this.LastCreatePayload = $Payload
            
            $id = [guid]::NewGuid().ToString()
            return @{
                id                = $id
                userPrincipalName = $Payload.userPrincipalName
                displayName       = $Payload.displayName
                accountEnabled    = $Payload.accountEnabled
            }
        } -Force

        $provider = New-IdleEntraIDIdentityProvider -Adapter $mockAdapter
        $script:PasswordTestProvider = $provider
        $script:PasswordTestAdapter = $mockAdapter
    }

    Context 'Password generation' {
        It 'Generates password when no PasswordProfile is provided' {
            $attrs = @{
                UserPrincipalName = 'newuser@contoso.com'
                DisplayName = 'New User'
            }

            $result = $script:PasswordTestProvider.CreateIdentity('newuser@contoso.com', $attrs, 'mock-token')
            
            # Verify password was generated
            $result.PasswordGenerated | Should -BeTrue
            $result.GeneratedAccountPasswordProtected | Should -Not -BeNullOrEmpty
            $result.PasswordGenerationMethod | Should -Be 'GUID'
        }

        It 'Does not include plaintext password by default' {
            $attrs = @{
                UserPrincipalName = 'user@contoso.com'
                DisplayName = 'User'
            }

            $result = $script:PasswordTestProvider.CreateIdentity('user@contoso.com', $attrs, 'mock-token')
            
            # Verify plaintext password is not included
            $result.PSObject.Properties.Name | Should -Not -Contain 'GeneratedAccountPasswordPlainText'
        }

        It 'Includes plaintext password when AllowPlainTextPasswordOutput is true' {
            $attrs = @{
                UserPrincipalName = 'user2@contoso.com'
                DisplayName = 'User 2'
                AllowPlainTextPasswordOutput = $true
            }

            $result = $script:PasswordTestProvider.CreateIdentity('user2@contoso.com', $attrs, 'mock-token')
            
            # Verify plaintext password is included
            $result.GeneratedAccountPasswordPlainText | Should -Not -BeNullOrEmpty
            $result.GeneratedAccountPasswordPlainText | Should -BeOfType [string]
            
            # Verify it's a GUID format
            { [guid]::Parse($result.GeneratedAccountPasswordPlainText) } | Should -Not -Throw
        }

        It 'Does not generate password when PasswordProfile is provided' {
            $attrs = @{
                UserPrincipalName = 'user3@contoso.com'
                DisplayName = 'User 3'
                PasswordProfile = @{
                    password = 'Explicit@Pass123!'
                    forceChangePasswordNextSignIn = $true
                }
            }

            $result = $script:PasswordTestProvider.CreateIdentity('user3@contoso.com', $attrs, 'mock-token')
            
            # Verify password was not generated (explicit password provided)
            $result.PSObject.Properties.Name | Should -Not -Contain 'PasswordGenerated'
        }

        It 'Sets forceChangePasswordNextSignIn to true by default' {
            $attrs = @{
                UserPrincipalName = 'user4@contoso.com'
                DisplayName = 'User 4'
            }

            $result = $script:PasswordTestProvider.CreateIdentity('user4@contoso.com', $attrs, 'mock-token')
            
            # Verify the payload sent to adapter
            $script:PasswordTestAdapter.LastCreatePayload.passwordProfile.forceChangePasswordNextSignIn | Should -BeTrue
        }

        It 'Allows ForceChangePasswordNextSignIn to be set to false' {
            $attrs = @{
                UserPrincipalName = 'serviceaccount@contoso.com'
                DisplayName = 'Service Account'
                ForceChangePasswordNextSignIn = $false
            }

            $result = $script:PasswordTestProvider.CreateIdentity('serviceaccount@contoso.com', $attrs, 'mock-token')
            
            # Verify the payload sent to adapter
            $script:PasswordTestAdapter.LastCreatePayload.passwordProfile.forceChangePasswordNextSignIn | Should -BeFalse
        }

        It 'Generated password can be revealed using ProtectedString' {
            $attrs = @{
                UserPrincipalName = 'user5@contoso.com'
                DisplayName = 'User 5'
            }

            $result = $script:PasswordTestProvider.CreateIdentity('user5@contoso.com', $attrs, 'mock-token')
            
            # Verify ProtectedString can be converted back to SecureString
            $protectedString = $result.GeneratedAccountPasswordProtected
            { ConvertTo-SecureString -String $protectedString } | Should -Not -Throw
            
            # Verify conversion works
            $secure = ConvertTo-SecureString -String $protectedString
            $secure | Should -BeOfType [securestring]
        }

        It 'Generated password is a valid GUID' {
            $attrs = @{
                UserPrincipalName = 'user6@contoso.com'
                DisplayName = 'User 6'
                AllowPlainTextPasswordOutput = $true
            }

            $result = $script:PasswordTestProvider.CreateIdentity('user6@contoso.com', $attrs, 'mock-token')
            
            # Verify the generated password is a valid GUID
            $plainPwd = $result.GeneratedAccountPasswordPlainText
            { [guid]::Parse($plainPwd) } | Should -Not -Throw
        }
    }
}

Describe 'EntraID identity provider - ResolveEntitlement' {
    BeforeAll {
        . (Join-Path (Split-Path -Path $PSScriptRoot -Parent) '_testHelpers.ps1')
        Import-IdleTestModule
    }

    Context 'Exposes ResolveEntitlement' {
        It 'Provider exposes ResolveEntitlement as a ScriptMethod' {
            $provider = New-IdleEntraIDIdentityProvider -Adapter ([pscustomobject]@{})
            $provider.PSObject.Methods.Name | Should -Contain 'ResolveEntitlement'
        }
    }

    Context 'ResolveEntitlement behavior' {
        BeforeAll {
            # Mock adapter that returns canonical objectId for groups and AUs (mimics real Graph lookup)
            $mockAdapter = [pscustomobject]@{ PSTypeName = 'IdLE.EntraIDAdapter.Mock'; Store = @{} }
            $mockAdapter | Add-Member -MemberType ScriptMethod -Name GetGroupById -Value {
                param($GroupId, $AccessToken)
                return @{ id = $GroupId; displayName = "Group $GroupId" }
            }
            $mockAdapter | Add-Member -MemberType ScriptMethod -Name GetGroupByDisplayName -Value {
                param($DisplayName, $AccessToken)
                return @{ id = "resolved-$DisplayName"; displayName = $DisplayName }
            }
            $mockAdapter | Add-Member -MemberType ScriptMethod -Name GetAdministrativeUnitById -Value {
                param($AuId, $AccessToken)
                return @{ id = $AuId; displayName = "AU $AuId" }
            }
            $mockAdapter | Add-Member -MemberType ScriptMethod -Name GetAdministrativeUnitByDisplayName -Value {
                param($DisplayName, $AccessToken)
                return @{ id = "resolved-au-$DisplayName"; displayName = $DisplayName }
            }
            $script:NormProvider = New-IdleEntraIDIdentityProvider -Adapter $mockAdapter
        }

        It 'Normalizes a Group entitlement with a GUID Id to canonical objectId' {
            $groupGuid = [guid]::NewGuid().ToString()
            $ent = @{ Kind = 'Group'; Id = $groupGuid }
            $result = $script:NormProvider.ResolveEntitlement('Group', $ent, 'mock-token')
            $result.Kind | Should -Be 'Group'
            $result.Id   | Should -Be $groupGuid
        }

        It 'Normalizes a Group entitlement with a displayName to canonical objectId' {
            $ent = @{ Kind = 'Group'; Id = 'HR Team' }
            $result = $script:NormProvider.ResolveEntitlement('Group', $ent, 'mock-token')
            $result.Kind | Should -Be 'Group'
            $result.Id   | Should -Be 'resolved-HR Team'
        }

        It 'Normalizes an AdministrativeUnit entitlement with a GUID Id to canonical objectId' {
            $auGuid = [guid]::NewGuid().ToString()
            $ent = @{ Kind = 'AdministrativeUnit'; Id = $auGuid }
            $result = $script:NormProvider.ResolveEntitlement('AdministrativeUnit', $ent, 'mock-token')
            $result.Kind | Should -Be 'AdministrativeUnit'
            $result.Id   | Should -Be $auGuid
        }

        It 'Normalizes an AdministrativeUnit entitlement with a displayName to canonical objectId' {
            $ent = @{ Kind = 'AdministrativeUnit'; Id = 'EU Region Admins' }
            $result = $script:NormProvider.ResolveEntitlement('AdministrativeUnit', $ent, 'mock-token')
            $result.Kind | Should -Be 'AdministrativeUnit'
            $result.Id   | Should -Be 'resolved-au-EU Region Admins'
        }

        It 'Returns entitlement unchanged when Kind is not Group' {
            $ent = [pscustomobject]@{ Kind = 'License'; Id = 'Some-License-Id' }
            $result = $script:NormProvider.ResolveEntitlement('License', $ent, 'mock-token')
            $result.Kind | Should -Be 'License'
            $result.Id   | Should -Be 'Some-License-Id'
        }
    }
}

Describe 'EntraID adapter - GetAllPages paging regression' {
    BeforeAll {
        . (Join-Path -Path $PSScriptRoot -ChildPath '..\_testHelpers.ps1')
        Import-IdleTestModule

        $repoRoot    = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
        $privatePath = Join-Path -Path $repoRoot -ChildPath 'src' 'IdLE.Provider.EntraID' 'Private'

        # Source private helpers so they are accessible in this test scope.
        # Get-IdleEntraIDGraphResponseProperty must be sourced before New-IdleEntraIDAdapter
        # so the script-method closures created inside New-IdleEntraIDAdapter can resolve it.
        . (Join-Path -Path $privatePath -ChildPath 'Get-IdleEntraIDGraphResponseProperty.ps1')
        . (Join-Path -Path $privatePath -ChildPath 'New-IdleEntraIDAdapter.ps1')
    }

    # Build an adapter whose InvokeGraphRequest returns a configurable sequence of pages.
    function script:New-EntraIDPagingTestAdapter {
        param([object[]] $PageSequence)

        $adapter = New-IdleEntraIDAdapter

        $script:EntraIDTestPages     = $PageSequence
        $script:EntraIDTestCallIndex = 0

        $adapter | Add-Member -MemberType ScriptMethod -Name InvokeGraphRequest -Value {
            param($Method, $Uri, $AccessToken, $Body)
            $result = $script:EntraIDTestPages[$script:EntraIDTestCallIndex]
            $script:EntraIDTestCallIndex++
            return $result
        } -Force

        return $adapter
    }

    Context 'Single-page response (PSCustomObject, no @odata.nextLink)' {
        It 'Returns all items and does not throw (the paging bug scenario)' {
            $page = [pscustomobject]@{
                value = @(
                    [pscustomobject]@{ id = 'g1'; displayName = 'Group 1' }
                    [pscustomobject]@{ id = 'g2'; displayName = 'Group 2' }
                )
                # @odata.nextLink intentionally absent — last page scenario that previously threw
            }

            $adapter = New-EntraIDPagingTestAdapter -PageSequence @($page)
            # Direct call; any thrown exception will fail this test automatically
            $result = $adapter.GetAllPages('https://graph.microsoft.com/v1.0/groups', 'mock-token')
            $result | Should -HaveCount 2
            $result[0].id | Should -Be 'g1'
            $result[1].id | Should -Be 'g2'
        }
    }

    Context 'Multi-page response (PSCustomObject, @odata.nextLink present on page 1)' {
        It 'Collects items from all pages' {
            $page1 = [pscustomobject]@{
                value              = @([pscustomobject]@{ id = 'g1' })
                '@odata.nextLink'  = 'https://graph.microsoft.com/v1.0/groups?$skiptoken=abc'
            }
            $page2 = [pscustomobject]@{
                value = @([pscustomobject]@{ id = 'g2' })
                # no @odata.nextLink on last page
            }

            $adapter = New-EntraIDPagingTestAdapter -PageSequence @($page1, $page2)
            $result  = $adapter.GetAllPages('https://graph.microsoft.com/v1.0/groups', 'mock-token')
            $result | Should -HaveCount 2
            ($result | Select-Object -ExpandProperty id) | Should -Contain 'g1'
            ($result | Select-Object -ExpandProperty id) | Should -Contain 'g2'
        }
    }

    Context 'Hashtable/IDictionary response' {
        It 'Returns items when response is a hashtable without @odata.nextLink' {
            $page = @{
                value = @(
                    @{ id = 'g1'; displayName = 'Group 1' }
                )
                # @odata.nextLink absent
            }

            $adapter = New-EntraIDPagingTestAdapter -PageSequence @($page)
            $result  = $null
            { $result = $adapter.GetAllPages('https://graph.microsoft.com/v1.0/groups', 'mock-token') } | Should -Not -Throw
            $result | Should -HaveCount 1
        }

        It 'Follows pagination when response is a hashtable with @odata.nextLink' {
            $page1 = @{
                value             = @(@{ id = 'g1' })
                '@odata.nextLink' = 'https://graph.microsoft.com/v1.0/groups?$skiptoken=ht'
            }
            $page2 = @{
                value = @(@{ id = 'g2' })
            }

            $adapter = New-EntraIDPagingTestAdapter -PageSequence @($page1, $page2)
            $result  = $adapter.GetAllPages('https://graph.microsoft.com/v1.0/groups', 'mock-token')
            $result | Should -HaveCount 2
        }
    }

    Context 'Response without a value wrapper (non-collection endpoint)' {
        It 'Returns empty array when response has no value property' {
            $page = [pscustomobject]@{ id = 'single-object'; displayName = 'Something' }

            $adapter = New-EntraIDPagingTestAdapter -PageSequence @($page)
            $result  = $adapter.GetAllPages('https://graph.microsoft.com/v1.0/something', 'mock-token')
            $result | Should -HaveCount 0
        }
    }

    Context 'Get-IdleEntraIDGraphResponseProperty helper' {
        It 'Returns property value from a PSCustomObject' {
            $obj    = [pscustomobject]@{ foo = 'bar' }
            $result = Get-IdleEntraIDGraphResponseProperty -InputObject $obj -PropertyName 'foo'
            $result | Should -Be 'bar'
        }

        It 'Returns $null for a missing property on PSCustomObject' {
            $obj    = [pscustomobject]@{ foo = 'bar' }
            $result = Get-IdleEntraIDGraphResponseProperty -InputObject $obj -PropertyName 'missing'
            $result | Should -BeNullOrEmpty
        }

        It 'Returns property value from a hashtable' {
            $ht     = @{ foo = 'baz' }
            $result = Get-IdleEntraIDGraphResponseProperty -InputObject $ht -PropertyName 'foo'
            $result | Should -Be 'baz'
        }

        It 'Returns $null for a missing key in a hashtable' {
            $ht     = @{ foo = 'baz' }
            $result = Get-IdleEntraIDGraphResponseProperty -InputObject $ht -PropertyName 'missing'
            $result | Should -BeNullOrEmpty
        }

        It 'Returns $null when InputObject is $null' {
            $result = Get-IdleEntraIDGraphResponseProperty -InputObject $null -PropertyName 'foo'
            $result | Should -BeNullOrEmpty
        }

        It 'Reads @odata.nextLink from PSCustomObject (the paging bug scenario)' {
            $obj    = [pscustomobject]@{ '@odata.nextLink' = 'https://next.page' ; value = @() }
            $result = Get-IdleEntraIDGraphResponseProperty -InputObject $obj -PropertyName '@odata.nextLink'
            $result | Should -Be 'https://next.page'
        }

        It 'Returns $null for @odata.nextLink when property is absent (last page scenario)' {
            $obj    = [pscustomobject]@{ value = @() }
            $result = Get-IdleEntraIDGraphResponseProperty -InputObject $obj -PropertyName '@odata.nextLink'
            $result | Should -BeNullOrEmpty
        }
    }
}

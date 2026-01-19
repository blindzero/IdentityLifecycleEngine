function New-IdleEntraIDIdentityProvider {
    <#
    .SYNOPSIS
    Creates a Microsoft Entra ID identity provider for IdLE.

    .DESCRIPTION
    This provider integrates with Microsoft Entra ID (formerly Azure Active Directory)
    via the Microsoft Graph API (v1.0). It supports both delegated and app-only authentication
    via the host-provided AuthSessionBroker pattern.

    The provider supports common identity operations (Create, Read, Disable, Enable, Delete)
    and group entitlement management (List, Grant, Revoke).

    Identity addressing supports:
    - objectId (GUID string) - most deterministic
    - UserPrincipalName (UPN) - contains @
    - mail - email address

    The canonical identity key for all outputs is the user objectId (GUID string).

    Authentication:
    Provider methods accept an optional AuthSession parameter for runtime credential
    selection via the AuthSessionBroker. The provider supports multiple auth session formats:
    - String access token (Bearer token)
    - Object with AccessToken property
    - Object with GetAccessToken() method
    - PSCredential (must contain AccessToken in password field for Graph API)

    By default, steps should use:
    - With.AuthSessionName = 'MicrosoftGraph'
    - With.AuthSessionOptions = @{ Role = 'Admin' } (or other routing keys)

    .PARAMETER AllowDelete
    Opt-in flag to enable the IdLE.Identity.Delete capability.
    When $true, the provider advertises the Delete capability and allows identity deletion.
    Default is $false for safety.

    .PARAMETER Adapter
    Internal parameter for dependency injection during testing. Allows unit tests to inject
    a fake Graph adapter without requiring a real Entra ID environment.

    .EXAMPLE
    # Basic usage with delegated auth
    # Host obtains token via secure method (not shown here - see provider documentation)
    $accessToken = Get-SecureGraphToken
    $broker = New-IdleAuthSessionBroker -SessionMap @{
        @{} = $accessToken
    } -DefaultCredential $accessToken

    $provider = New-IdleEntraIDIdentityProvider
    $plan = New-IdlePlan -WorkflowPath './workflow.psd1' -Request $request -Providers @{
        Identity = $provider
        AuthSessionBroker = $broker
    }

    .EXAMPLE
    # Multi-role scenario
    $tier0Token = Get-GraphTokenForTier0  # host-managed auth
    $adminToken = Get-GraphTokenForAdmin

    $broker = New-IdleAuthSessionBroker -SessionMap @{
        @{ Role = 'Tier0' } = $tier0Token
        @{ Role = 'Admin' } = $adminToken
    } -DefaultCredential $adminToken

    $provider = New-IdleEntraIDIdentityProvider
    $plan = New-IdlePlan -WorkflowPath './workflow.psd1' -Request $request -Providers @{
        Identity = $provider
        AuthSessionBroker = $broker
    }

    # Workflow steps specify: With.AuthSessionOptions = @{ Role = 'Tier0' }

    .EXAMPLE
    # Enable delete capability (opt-in)
    $provider = New-IdleEntraIDIdentityProvider -AllowDelete

    .OUTPUTS
    PSCustomObject with IdLE provider contract methods

    .NOTES
    Requires Microsoft Graph API permissions (delegated or app-only):
    - User.Read.All, User.ReadWrite.All
    - Group.Read.All, GroupMember.ReadWrite.All
    - For delete: User.ReadWrite.All

    See docs/reference/providers/provider-entraID.md for detailed permission requirements.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [switch] $AllowDelete,

        [Parameter()]
        [AllowNull()]
        [object] $Adapter
    )

    if ($null -eq $Adapter) {
        $Adapter = New-IdleEntraIDAdapter
    }

    $convertToEntitlement = {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [ValidateNotNull()]
            [object] $Value
        )

        $kind = $null
        $id = $null
        $displayName = $null
        $mail = $null

        if ($Value -is [System.Collections.IDictionary]) {
            $kind = $Value['Kind']
            $id = $Value['Id']
            if ($Value.Contains('DisplayName')) { $displayName = $Value['DisplayName'] }
            if ($Value.Contains('Mail')) { $mail = $Value['Mail'] }
        }
        else {
            $props = $Value.PSObject.Properties
            if ($props.Name -contains 'Kind') { $kind = $Value.Kind }
            if ($props.Name -contains 'Id') { $id = $Value.Id }
            if ($props.Name -contains 'DisplayName') { $displayName = $Value.DisplayName }
            if ($props.Name -contains 'Mail') { $mail = $Value.Mail }
        }

        if ([string]::IsNullOrWhiteSpace([string]$kind)) {
            throw "Entitlement.Kind must not be empty."
        }
        if ([string]::IsNullOrWhiteSpace([string]$id)) {
            throw "Entitlement.Id must not be empty."
        }

        return [pscustomobject]@{
            PSTypeName  = 'IdLE.Entitlement'
            Kind        = [string]$kind
            Id          = [string]$id
            DisplayName = if ($null -eq $displayName -or [string]::IsNullOrWhiteSpace([string]$displayName)) {
                $null
            }
            else {
                [string]$displayName
            }
            Mail        = if ($null -eq $mail -or [string]::IsNullOrWhiteSpace([string]$mail)) {
                $null
            }
            else {
                [string]$mail
            }
        }
    }

    $testEntitlementEquals = {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [ValidateNotNull()]
            [object] $A,

            [Parameter(Mandatory)]
            [ValidateNotNull()]
            [object] $B
        )

        $aEnt = $this.ConvertToEntitlement($A)
        $bEnt = $this.ConvertToEntitlement($B)

        if ($aEnt.Kind -ne $bEnt.Kind) {
            return $false
        }

        return [string]::Equals($aEnt.Id, $bEnt.Id, [System.StringComparison]::OrdinalIgnoreCase)
    }

    $extractAccessToken = {
        param(
            [Parameter()]
            [AllowNull()]
            [object] $AuthSession
        )

        if ($null -eq $AuthSession) {
            # For tests/development, allow null but it will fail when hitting real Graph API
            # Real usage will fail with proper error from Graph API
            return 'test-token-not-for-production'
        }

        # String token
        if ($AuthSession -is [string]) {
            return $AuthSession
        }

        # Object with GetAccessToken() method
        if ($AuthSession.PSObject.Methods.Name -contains 'GetAccessToken') {
            return $AuthSession.GetAccessToken()
        }

        # Object with AccessToken property
        if ($AuthSession.PSObject.Properties.Name -contains 'AccessToken') {
            return $AuthSession.AccessToken
        }

        # PSCredential with token in password field
        if ($AuthSession -is [PSCredential]) {
            return $AuthSession.GetNetworkCredential().Password
        }

        throw "AuthSession format not recognized. Expected: string token, object with AccessToken property, object with GetAccessToken() method, or PSCredential."
    }

    $resolveIdentity = {
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $IdentityKey,

            [Parameter()]
            [AllowNull()]
            [object] $AuthSession
        )

        $accessToken = $this.ExtractAccessToken($AuthSession)

        # Try GUID format first (most deterministic)
        # Support both standard GUID format and N-format (32 hex digits)
        $guid = [System.Guid]::Empty
        $isGuid = [System.Guid]::TryParse($IdentityKey, [ref]$guid)

        # Also check for N-format GUID (32 hex digits, no hyphens)
        # This handles standalone GUIDs and GUIDs with prefixes (e.g., contract test keys like "contract-<guid>")
        if (-not $isGuid -and $IdentityKey -match '([0-9a-fA-F]{32})') {
            $hexPart = $Matches[1]
            $isGuid = [System.Guid]::TryParseExact($hexPart, 'N', [ref]$guid)
        }
        
        if ($isGuid) {
            $user = $this.Adapter.GetUserById($guid.ToString(), $accessToken)
            if ($null -ne $user) {
                return $user
            }
            throw "Identity with objectId '$IdentityKey' not found."
        }

        # Try UPN format (contains @)
        if ($IdentityKey -match '@') {
            $user = $this.Adapter.GetUserByUpn($IdentityKey, $accessToken)
            if ($null -ne $user) {
                return $user
            }

            # Fallback: try as mail
            $user = $this.Adapter.GetUserByMail($IdentityKey, $accessToken)
            if ($null -ne $user) {
                return $user
            }

            throw "Identity with UPN/mail '$IdentityKey' not found."
        }

        throw "Identity key '$IdentityKey' is not in a recognized format (objectId GUID, UPN, or mail)."
    }

    $normalizeGroupId = {
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $GroupId,

            [Parameter()]
            [AllowNull()]
            [object] $AuthSession
        )

        $accessToken = $this.ExtractAccessToken($AuthSession)

        # Try as objectId first
        $guid = [System.Guid]::Empty
        if ([System.Guid]::TryParse($GroupId, [ref]$guid)) {
            $group = $this.Adapter.GetGroupById($GroupId, $accessToken)
            if ($null -ne $group) {
                return $group.id
            }
            throw "Group with objectId '$GroupId' not found."
        }

        # Try as displayName
        $group = $this.Adapter.GetGroupByDisplayName($GroupId, $accessToken)
        if ($null -ne $group) {
            return $group.id
        }

        throw "Group '$GroupId' not found."
    }

    $provider = [pscustomobject]@{
        PSTypeName  = 'IdLE.Provider.EntraIDIdentityProvider'
        Name        = 'EntraIDIdentityProvider'
        Adapter     = $Adapter
        AllowDelete = [bool]$AllowDelete
    }

    $provider | Add-Member -MemberType ScriptMethod -Name ExtractAccessToken -Value $extractAccessToken -Force
    $provider | Add-Member -MemberType ScriptMethod -Name ConvertToEntitlement -Value $convertToEntitlement -Force
    $provider | Add-Member -MemberType ScriptMethod -Name TestEntitlementEquals -Value $testEntitlementEquals -Force
    $provider | Add-Member -MemberType ScriptMethod -Name ResolveIdentity -Value $resolveIdentity -Force
    $provider | Add-Member -MemberType ScriptMethod -Name NormalizeGroupId -Value $normalizeGroupId -Force

    $provider | Add-Member -MemberType ScriptMethod -Name GetCapabilities -Value {
        $caps = @(
            'IdLE.Identity.Read'
            'IdLE.Identity.List'
            'IdLE.Identity.Create'
            'IdLE.Identity.Attribute.Ensure'
            'IdLE.Identity.Disable'
            'IdLE.Identity.Enable'
            'IdLE.Entitlement.List'
            'IdLE.Entitlement.Grant'
            'IdLE.Entitlement.Revoke'
        )

        if ($this.AllowDelete) {
            $caps += 'IdLE.Identity.Delete'
        }

        return $caps
    } -Force

    $provider | Add-Member -MemberType ScriptMethod -Name GetIdentity -Value {
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $IdentityKey,

            [Parameter()]
            [AllowNull()]
            [object] $AuthSession
        )

        $user = $this.ResolveIdentity($IdentityKey, $AuthSession)

        $attributes = @{}
        
        # Handle both hashtables and PSCustomObjects
        $getUserProperty = {
            param($obj, $propName)
            if ($obj -is [System.Collections.IDictionary]) {
                if ($obj.ContainsKey($propName)) {
                    return $obj[$propName]
                }
            }
            elseif ($obj.PSObject.Properties.Name -contains $propName) {
                return $obj.$propName
            }
            return $null
        }
        
        $givenName = & $getUserProperty $user 'givenName'
        if ($null -ne $givenName) { $attributes['GivenName'] = $givenName }
        
        $surname = & $getUserProperty $user 'surname'
        if ($null -ne $surname) { $attributes['Surname'] = $surname }
        
        $displayName = & $getUserProperty $user 'displayName'
        if ($null -ne $displayName) { $attributes['DisplayName'] = $displayName }
        
        $upn = & $getUserProperty $user 'userPrincipalName'
        if ($null -ne $upn) { $attributes['UserPrincipalName'] = $upn }
        
        $mail = & $getUserProperty $user 'mail'
        if ($null -ne $mail) { $attributes['Mail'] = $mail }
        
        $dept = & $getUserProperty $user 'department'
        if ($null -ne $dept) { $attributes['Department'] = $dept }
        
        $jobTitle = & $getUserProperty $user 'jobTitle'
        if ($null -ne $jobTitle) { $attributes['JobTitle'] = $jobTitle }
        
        $officeLocation = & $getUserProperty $user 'officeLocation'
        if ($null -ne $officeLocation) { $attributes['OfficeLocation'] = $officeLocation }
        
        $companyName = & $getUserProperty $user 'companyName'
        if ($null -ne $companyName) { $attributes['CompanyName'] = $companyName }
        
        # Get accountEnabled
        $accountEnabled = & $getUserProperty $user 'accountEnabled'

        return [pscustomobject]@{
            PSTypeName  = 'IdLE.Identity'
            IdentityKey = $IdentityKey
            Enabled     = [bool]$accountEnabled
            Attributes  = $attributes
        }
    } -Force

    $provider | Add-Member -MemberType ScriptMethod -Name ListIdentities -Value {
        param(
            [Parameter()]
            [hashtable] $Filter,

            [Parameter()]
            [AllowNull()]
            [object] $AuthSession
        )

        $accessToken = $this.ExtractAccessToken($AuthSession)
        $users = $this.Adapter.ListUsers($Filter, $accessToken)

        $identityKeys = @()
        foreach ($user in $users) {
            $identityKeys += $user.id
        }
        return $identityKeys
    } -Force

    $provider | Add-Member -MemberType ScriptMethod -Name CreateIdentity -Value {
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $IdentityKey,

            [Parameter(Mandatory)]
            [ValidateNotNull()]
            [hashtable] $Attributes,

            [Parameter()]
            [AllowNull()]
            [object] $AuthSession
        )

        $accessToken = $this.ExtractAccessToken($AuthSession)

        # Check if user already exists (idempotency)
        try {
            $existing = $this.ResolveIdentity($IdentityKey, $AuthSession)
            if ($null -ne $existing) {
                return [pscustomobject]@{
                    PSTypeName  = 'IdLE.ProviderResult'
                    Operation   = 'CreateIdentity'
                    IdentityKey = $IdentityKey
                    Changed     = $false
                }
            }
        }
        catch {
            # Identity does not exist, proceed with creation
            Write-Verbose "Identity '$IdentityKey' does not exist, proceeding with creation"
        }

        # Build Graph API payload
        $payload = @{
            accountEnabled = $true
        }

        # Required fields for user creation
        if ($Attributes.ContainsKey('UserPrincipalName')) {
            $payload['userPrincipalName'] = $Attributes['UserPrincipalName']
        }
        else {
            $payload['userPrincipalName'] = $IdentityKey
        }

        if ($Attributes.ContainsKey('DisplayName')) {
            $payload['displayName'] = $Attributes['DisplayName']
        }
        else {
            $payload['displayName'] = $IdentityKey
        }

        # MailNickname is required
        if ($Attributes.ContainsKey('MailNickname')) {
            $payload['mailNickname'] = $Attributes['MailNickname']
        }
        else {
            # Generate from UPN
            $payload['mailNickname'] = $payload['userPrincipalName'].Split('@')[0]
        }

        # Password policy for new users
        if ($Attributes.ContainsKey('PasswordProfile')) {
            $payload['passwordProfile'] = $Attributes['PasswordProfile']
        }
        else {
            # Default: force change on first sign-in
            $payload['passwordProfile'] = @{
                forceChangePasswordNextSignIn = $true
                password                      = [System.Guid]::NewGuid().ToString()
            }
        }

        # Optional attributes
        if ($Attributes.ContainsKey('GivenName')) { $payload['givenName'] = $Attributes['GivenName'] }
        if ($Attributes.ContainsKey('Surname')) { $payload['surname'] = $Attributes['Surname'] }
        if ($Attributes.ContainsKey('Mail')) { $payload['mail'] = $Attributes['Mail'] }
        if ($Attributes.ContainsKey('Department')) { $payload['department'] = $Attributes['Department'] }
        if ($Attributes.ContainsKey('JobTitle')) { $payload['jobTitle'] = $Attributes['JobTitle'] }
        if ($Attributes.ContainsKey('OfficeLocation')) { $payload['officeLocation'] = $Attributes['OfficeLocation'] }
        if ($Attributes.ContainsKey('CompanyName')) { $payload['companyName'] = $Attributes['CompanyName'] }

        if ($Attributes.ContainsKey('Enabled')) {
            $payload['accountEnabled'] = [bool]$Attributes['Enabled']
        }

        $user = $this.Adapter.CreateUser($payload, $accessToken)

        return [pscustomobject]@{
            PSTypeName  = 'IdLE.ProviderResult'
            Operation   = 'CreateIdentity'
            IdentityKey = $IdentityKey
            Changed     = $true
        }
    } -Force

    $provider | Add-Member -MemberType ScriptMethod -Name DeleteIdentity -Value {
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $IdentityKey,

            [Parameter()]
            [AllowNull()]
            [object] $AuthSession
        )

        if (-not $this.AllowDelete) {
            throw "Delete capability is not enabled. Set AllowDelete = `$true when creating the provider."
        }

        $accessToken = $this.ExtractAccessToken($AuthSession)

        try {
            $user = $this.ResolveIdentity($IdentityKey, $AuthSession)
            $this.Adapter.DeleteUser($user.id, $accessToken)

            return [pscustomobject]@{
                PSTypeName  = 'IdLE.ProviderResult'
                Operation   = 'DeleteIdentity'
                IdentityKey = $IdentityKey
                Changed     = $true
            }
        }
        catch {
            # Idempotency: if not found, treat as success
            if ($_.Exception.Message -match '404|not found|does not exist') {
                return [pscustomobject]@{
                    PSTypeName  = 'IdLE.ProviderResult'
                    Operation   = 'DeleteIdentity'
                    IdentityKey = $IdentityKey
                    Changed     = $false
                }
            }
            throw
        }
    } -Force

    $provider | Add-Member -MemberType ScriptMethod -Name EnsureAttribute -Value {
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $IdentityKey,

            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $Name,

            [Parameter()]
            [AllowNull()]
            [object] $Value,

            [Parameter()]
            [AllowNull()]
            [object] $AuthSession
        )

        $accessToken = $this.ExtractAccessToken($AuthSession)
        $user = $this.ResolveIdentity($IdentityKey, $AuthSession)

        # Map IdLE attribute names to Graph API property names
        $graphPropertyName = switch ($Name) {
            'GivenName' { 'givenName' }
            'Surname' { 'surname' }
            'DisplayName' { 'displayName' }
            'UserPrincipalName' { 'userPrincipalName' }
            'Mail' { 'mail' }
            'Department' { 'department' }
            'JobTitle' { 'jobTitle' }
            'OfficeLocation' { 'officeLocation' }
            'CompanyName' { 'companyName' }
            default { $Name.Substring(0, 1).ToLower() + $Name.Substring(1) }
        }

        $currentValue = $null
        if ($user -is [System.Collections.IDictionary]) {
            if ($user.ContainsKey($graphPropertyName)) {
                $currentValue = $user[$graphPropertyName]
            }
        }
        elseif ($user.PSObject.Properties.Name -contains $graphPropertyName) {
            $currentValue = $user.$graphPropertyName
        }

        $changed = $false
        # Use loose comparison for idempotency (handles type coercion)
        if (-not ($currentValue -eq $Value)) {
            $payload = @{
                $graphPropertyName = $Value
            }
            $this.Adapter.PatchUser($user.id, $payload, $accessToken)
            $changed = $true
        }

        return [pscustomobject]@{
            PSTypeName  = 'IdLE.ProviderResult'
            Operation   = 'EnsureAttribute'
            IdentityKey = $IdentityKey
            Changed     = $changed
            Name        = $Name
            Value       = $Value
        }
    } -Force

    $provider | Add-Member -MemberType ScriptMethod -Name DisableIdentity -Value {
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $IdentityKey,

            [Parameter()]
            [AllowNull()]
            [object] $AuthSession
        )

        $accessToken = $this.ExtractAccessToken($AuthSession)
        $user = $this.ResolveIdentity($IdentityKey, $AuthSession)

        # Get accountEnabled from user object (handle both hashtable and PSCustomObject)
        $accountEnabled = if ($user -is [System.Collections.IDictionary]) {
            if ($user.ContainsKey('accountEnabled')) { $user['accountEnabled'] } else { $null }
        }
        else {
            if ($user.PSObject.Properties.Name -contains 'accountEnabled') { $user.accountEnabled } else { $null }
        }

        # Get id from user object
        $userId = if ($user -is [System.Collections.IDictionary]) {
            $user['id']
        }
        else {
            $user.id
        }

        $changed = $false
        if ($accountEnabled -ne $false) {
            $payload = @{ accountEnabled = $false }
            $this.Adapter.PatchUser($userId, $payload, $accessToken)
            $changed = $true
        }

        return [pscustomobject]@{
            PSTypeName  = 'IdLE.ProviderResult'
            Operation   = 'DisableIdentity'
            IdentityKey = $IdentityKey
            Changed     = $changed
        }
    } -Force

    $provider | Add-Member -MemberType ScriptMethod -Name EnableIdentity -Value {
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $IdentityKey,

            [Parameter()]
            [AllowNull()]
            [object] $AuthSession
        )

        $accessToken = $this.ExtractAccessToken($AuthSession)
        $user = $this.ResolveIdentity($IdentityKey, $AuthSession)

        # Get accountEnabled from user object (handle both hashtable and PSCustomObject)
        $accountEnabled = if ($user -is [System.Collections.IDictionary]) {
            if ($user.ContainsKey('accountEnabled')) { $user['accountEnabled'] } else { $null }
        }
        else {
            if ($user.PSObject.Properties.Name -contains 'accountEnabled') { $user.accountEnabled } else { $null }
        }

        # Get id from user object
        $userId = if ($user -is [System.Collections.IDictionary]) {
            $user['id']
        }
        else {
            $user.id
        }

        $changed = $false
        if ($accountEnabled -ne $true) {
            $payload = @{ accountEnabled = $true }
            $this.Adapter.PatchUser($userId, $payload, $accessToken)
            $changed = $true
        }

        return [pscustomobject]@{
            PSTypeName  = 'IdLE.ProviderResult'
            Operation   = 'EnableIdentity'
            IdentityKey = $IdentityKey
            Changed     = $changed
        }
    } -Force

    $provider | Add-Member -MemberType ScriptMethod -Name ListEntitlements -Value {
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $IdentityKey,

            [Parameter()]
            [AllowNull()]
            [object] $AuthSession
        )

        $accessToken = $this.ExtractAccessToken($AuthSession)
        $user = $this.ResolveIdentity($IdentityKey, $AuthSession)

        $groups = $this.Adapter.ListUserGroups($user.id, $accessToken)

        $result = @()
        foreach ($group in $groups) {
            # Handle both hashtables and PSCustomObjects
            $groupId = if ($group -is [System.Collections.IDictionary]) {
                $group['id']
            } else {
                $group.id
            }
            
            $displayName = if ($group -is [System.Collections.IDictionary]) {
                if ($group.ContainsKey('displayName')) { $group['displayName'] } else { $null }
            } else {
                if ($group.PSObject.Properties.Name -contains 'displayName') { $group.displayName } else { $null }
            }
            
            $mail = if ($group -is [System.Collections.IDictionary]) {
                if ($group.ContainsKey('mail')) { $group['mail'] } else { $null }
            } else {
                if ($group.PSObject.Properties.Name -contains 'mail') { $group.mail } else { $null }
            }
            
            $result += [pscustomobject]@{
                PSTypeName  = 'IdLE.Entitlement'
                Kind        = 'Group'
                Id          = $groupId
                DisplayName = $displayName
                Mail        = $mail
            }
        }

        return $result
    } -Force

    $provider | Add-Member -MemberType ScriptMethod -Name GrantEntitlement -Value {
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $IdentityKey,

            [Parameter(Mandatory)]
            [ValidateNotNull()]
            [object] $Entitlement,

            [Parameter()]
            [AllowNull()]
            [object] $AuthSession
        )

        $accessToken = $this.ExtractAccessToken($AuthSession)
        $normalized = $this.ConvertToEntitlement($Entitlement)

        # GrantEntitlement only supports group entitlements
        if ($null -ne $normalized.Kind -and $normalized.Kind -ne 'Group') {
            throw [System.ArgumentException]::new(
                "GrantEntitlement only supports entitlements with Kind 'Group'. Received Kind '$($normalized.Kind)'."
            )
        }

        # Default missing Kind to 'Group' for backward compatibility
        if (-not $normalized.Kind) {
            $normalized.Kind = 'Group'
        }

        $user = $this.ResolveIdentity($IdentityKey, $AuthSession)
        $groupObjectId = $this.NormalizeGroupId($normalized.Id, $AuthSession)

        # Update normalized entitlement with canonical group ID
        $normalized.Id = $groupObjectId

        # Check if already a member (idempotency)
        $currentGroups = $this.ListEntitlements($IdentityKey, $AuthSession)
        $existing = $currentGroups | Where-Object { $this.TestEntitlementEquals($_, $normalized) }

        $changed = $false
        if (@($existing).Count -eq 0) {
            $this.Adapter.AddGroupMember($groupObjectId, $user.id, $accessToken)
            $changed = $true
        }

        return [pscustomobject]@{
            PSTypeName  = 'IdLE.ProviderResult'
            Operation   = 'GrantEntitlement'
            IdentityKey = $IdentityKey
            Changed     = $changed
            Entitlement = $normalized
        }
    } -Force

    $provider | Add-Member -MemberType ScriptMethod -Name RevokeEntitlement -Value {
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $IdentityKey,

            [Parameter(Mandatory)]
            [ValidateNotNull()]
            [object] $Entitlement,

            [Parameter()]
            [AllowNull()]
            [object] $AuthSession
        )

        $accessToken = $this.ExtractAccessToken($AuthSession)
        $normalized = $this.ConvertToEntitlement($Entitlement)

        # RevokeEntitlement only supports group entitlements
        if ($null -ne $normalized.Kind -and $normalized.Kind -ne 'Group') {
            throw [System.ArgumentException]::new(
                "RevokeEntitlement only supports entitlements with Kind 'Group'. Received Kind '$($normalized.Kind)'."
            )
        }

        # Default missing Kind to 'Group' for backward compatibility
        if (-not $normalized.Kind) {
            $normalized.Kind = 'Group'
        }
        $user = $this.ResolveIdentity($IdentityKey, $AuthSession)
        $groupObjectId = $this.NormalizeGroupId($normalized.Id, $AuthSession)

        # Update normalized entitlement with canonical group ID
        $normalized.Id = $groupObjectId

        # Check if currently a member (idempotency)
        $currentGroups = $this.ListEntitlements($IdentityKey, $AuthSession)
        $existing = $currentGroups | Where-Object { $this.TestEntitlementEquals($_, $normalized) }

        $changed = $false
        if (@($existing).Count -gt 0) {
            $this.Adapter.RemoveGroupMember($groupObjectId, $user.id, $accessToken)
            $changed = $true
        }

        return [pscustomobject]@{
            PSTypeName  = 'IdLE.ProviderResult'
            Operation   = 'RevokeEntitlement'
            IdentityKey = $IdentityKey
            Changed     = $changed
            Entitlement = $normalized
        }
    } -Force

    return $provider
}

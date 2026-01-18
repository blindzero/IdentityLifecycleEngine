function New-IdleADIdentityProvider {
    <#
    .SYNOPSIS
    Creates an Active Directory identity provider for IdLE.

    .DESCRIPTION
    This provider integrates with on-premises Active Directory environments.
    It requires the ActiveDirectory PowerShell module (RSAT) and runs on Windows only.

    The provider supports common identity operations (Create, Read, Disable, Enable, Move, Delete)
    and group entitlement management (List, Grant, Revoke).

    Identity addressing supports:
    - GUID (ObjectGuid) - pattern: ^[0-9a-fA-F-]{36}$ or N-format
    - UPN (UserPrincipalName) - contains @
    - sAMAccountName - default fallback

    .PARAMETER Credential
    Optional PSCredential for AD operations. If not provided, uses integrated auth (run-as).

    .PARAMETER AllowDelete
    Opt-in flag to enable the IdLE.Identity.Delete capability.
    When $true, the provider advertises the Delete capability and allows identity deletion.
    Default is $false for safety.

    .PARAMETER Adapter
    Internal parameter for dependency injection during testing. Allows unit tests to inject
    a fake AD adapter without requiring a real Active Directory environment.

    .EXAMPLE
    $provider = New-IdleADIdentityProvider
    $provider.GetIdentity('user@domain.com')

    .EXAMPLE
    $cred = Get-Credential
    $provider = New-IdleADIdentityProvider -Credential $cred -AllowDelete $true
    $provider.DeleteIdentity('user@domain.com')
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [PSCredential] $Credential,

        [Parameter()]
        [switch] $AllowDelete,

        [Parameter()]
        [AllowNull()]
        [object] $Adapter
    )

    if ($null -eq $Adapter) {
        $Adapter = New-IdleADAdapter -Credential $Credential
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

        if ($Value -is [System.Collections.IDictionary]) {
            $kind = $Value['Kind']
            $id = $Value['Id']
            if ($Value.Contains('DisplayName')) { $displayName = $Value['DisplayName'] }
        }
        else {
            $props = $Value.PSObject.Properties
            if ($props.Name -contains 'Kind') { $kind = $Value.Kind }
            if ($props.Name -contains 'Id') { $id = $Value.Id }
            if ($props.Name -contains 'DisplayName') { $displayName = $Value.DisplayName }
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

    $resolveIdentity = {
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $IdentityKey
        )

        # Try GUID format first (most deterministic)
        $guid = [System.Guid]::Empty
        if ([System.Guid]::TryParse($IdentityKey, [ref]$guid)) {
            try {
                $user = $this.Adapter.GetUserByGuid($guid.ToString())
            }
            catch [System.Management.Automation.MethodException] {
                Write-Verbose "GetUserByGuid failed for GUID '$IdentityKey': $_"
                $user = $null
            }

            if ($null -ne $user) {
                return $user
            }
            throw "Identity with GUID '$IdentityKey' not found."
        }

        # Try UPN format (contains @)
        if ($IdentityKey -match '@') {
            $user = $this.Adapter.GetUserByUpn($IdentityKey)
            if ($null -ne $user) {
                return $user
            }
            throw "Identity with UPN '$IdentityKey' not found."
        }

        # Fallback to sAMAccountName
        $user = $this.Adapter.GetUserBySam($IdentityKey)
        if ($null -ne $user) {
            return $user
        }
        throw "Identity with sAMAccountName '$IdentityKey' not found."
    }

    $normalizeGroupId = {
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $GroupId
        )

        $group = $this.Adapter.GetGroupById($GroupId)
        if ($null -eq $group) {
            throw "Group '$GroupId' not found."
        }

        return $group.DistinguishedName
    }

    $provider = [pscustomobject]@{
        PSTypeName  = 'IdLE.Provider.ADIdentityProvider'
        Name        = 'ADIdentityProvider'
        Adapter     = $Adapter
        AllowDelete = [bool]$AllowDelete
    }

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
            'IdLE.Identity.Move'
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
            [string] $IdentityKey
        )

        $user = $this.ResolveIdentity($IdentityKey)

        $attributes = @{}
        if ($null -ne $user.GivenName) { $attributes['GivenName'] = $user.GivenName }
        if ($null -ne $user.Surname) { $attributes['Surname'] = $user.Surname }
        if ($null -ne $user.DisplayName) { $attributes['DisplayName'] = $user.DisplayName }
        if ($null -ne $user.Description) { $attributes['Description'] = $user.Description }
        if ($null -ne $user.Department) { $attributes['Department'] = $user.Department }
        if ($null -ne $user.Title) { $attributes['Title'] = $user.Title }
        if ($null -ne $user.EmailAddress) { $attributes['EmailAddress'] = $user.EmailAddress }
        if ($null -ne $user.UserPrincipalName) { $attributes['UserPrincipalName'] = $user.UserPrincipalName }
        if ($null -ne $user.sAMAccountName) { $attributes['sAMAccountName'] = $user.sAMAccountName }
        if ($null -ne $user.DistinguishedName) { $attributes['DistinguishedName'] = $user.DistinguishedName }

        return [pscustomobject]@{
            PSTypeName  = 'IdLE.Identity'
            IdentityKey = $IdentityKey
            Enabled     = [bool]$user.Enabled
            Attributes  = $attributes
        }
    } -Force

    $provider | Add-Member -MemberType ScriptMethod -Name ListIdentities -Value {
        param(
            [Parameter()]
            [hashtable] $Filter
        )

        $users = $this.Adapter.ListUsers($Filter)
        $identityKeys = @()
        foreach ($user in $users) {
            $identityKeys += $user.ObjectGuid.ToString()
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
            [hashtable] $Attributes
        )

        try {
            $existing = $this.ResolveIdentity($IdentityKey)
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
            # Identity does not exist, proceed with creation (expected for idempotent create)
        }

        $enabled = $true
        if ($Attributes.ContainsKey('Enabled')) {
            $enabled = [bool]$Attributes['Enabled']
        }

        $user = $this.Adapter.NewUser($IdentityKey, $Attributes, $enabled)

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
            [string] $IdentityKey
        )

        if (-not $this.AllowDelete) {
            throw "Delete capability is not enabled. Set AllowDelete = `$true when creating the provider."
        }

        try {
            $user = $this.ResolveIdentity($IdentityKey)
            $this.Adapter.DeleteUser($user.DistinguishedName)
            return [pscustomobject]@{
                PSTypeName  = 'IdLE.ProviderResult'
                Operation   = 'DeleteIdentity'
                IdentityKey = $IdentityKey
                Changed     = $true
            }
        }
        catch {
            # Check if identity doesn't exist (idempotent delete)
            # Use exception type if available, otherwise fall back to message check
            $isNotFound = $false
            if ($_.Exception.GetType().FullName -eq 'Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException') {
                $isNotFound = $true
            }
            elseif ($_.Exception.Message -match 'not found|cannot be found|does not exist') {
                $isNotFound = $true
            }

            if ($isNotFound) {
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
            [object] $Value
        )

        $user = $this.ResolveIdentity($IdentityKey)

        $currentValue = $null
        if ($user.PSObject.Properties.Name -contains $Name) {
            $currentValue = $user.$Name
        }

        $changed = $false
        if ($currentValue -ne $Value) {
            $this.Adapter.SetUser($user.DistinguishedName, $Name, $Value)
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

    $provider | Add-Member -MemberType ScriptMethod -Name MoveIdentity -Value {
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $IdentityKey,

            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $TargetContainer
        )

        $user = $this.ResolveIdentity($IdentityKey)

        $currentOu = $user.DistinguishedName -replace '^CN=[^,]+,', ''

        $changed = $false
        if ($currentOu -ne $TargetContainer) {
            $this.Adapter.MoveObject($user.DistinguishedName, $TargetContainer)
            $changed = $true
        }

        return [pscustomobject]@{
            PSTypeName       = 'IdLE.ProviderResult'
            Operation        = 'MoveIdentity'
            IdentityKey      = $IdentityKey
            Changed          = $changed
            TargetContainer  = $TargetContainer
        }
    } -Force

    $provider | Add-Member -MemberType ScriptMethod -Name DisableIdentity -Value {
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $IdentityKey
        )

        $user = $this.ResolveIdentity($IdentityKey)

        $changed = $false
        if ($user.Enabled -ne $false) {
            $this.Adapter.DisableUser($user.DistinguishedName)
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
            [string] $IdentityKey
        )

        $user = $this.ResolveIdentity($IdentityKey)

        $changed = $false
        if ($user.Enabled -ne $true) {
            $this.Adapter.EnableUser($user.DistinguishedName)
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
            [string] $IdentityKey
        )

        $user = $this.ResolveIdentity($IdentityKey)
        $groups = $this.Adapter.GetUserGroups($user.DistinguishedName)

        $result = @()
        foreach ($group in $groups) {
            $result += [pscustomobject]@{
                PSTypeName  = 'IdLE.Entitlement'
                Kind        = 'Group'
                Id          = $group.DistinguishedName
                DisplayName = $group.Name
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
            [object] $Entitlement
        )

        $normalized = $this.ConvertToEntitlement($Entitlement)
        $user = $this.ResolveIdentity($IdentityKey)
        $groupDn = $this.NormalizeGroupId($normalized.Id)

        $currentGroups = $this.ListEntitlements($IdentityKey)
        $existing = $currentGroups | Where-Object { $this.TestEntitlementEquals($_, $normalized) }

        $changed = $false
        if (@($existing).Count -eq 0) {
            $this.Adapter.AddGroupMember($groupDn, $user.DistinguishedName)
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
            [object] $Entitlement
        )

        $normalized = $this.ConvertToEntitlement($Entitlement)
        $user = $this.ResolveIdentity($IdentityKey)
        $groupDn = $this.NormalizeGroupId($normalized.Id)

        $currentGroups = $this.ListEntitlements($IdentityKey)
        $existing = $currentGroups | Where-Object { $this.TestEntitlementEquals($_, $normalized) }

        $changed = $false
        if (@($existing).Count -gt 0) {
            $this.Adapter.RemoveGroupMember($groupDn, $user.DistinguishedName)
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

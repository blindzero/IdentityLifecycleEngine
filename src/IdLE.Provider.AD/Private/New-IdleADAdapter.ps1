function New-IdleADAdapter {
    <#
    .SYNOPSIS
    Creates an internal adapter that wraps Active Directory cmdlets.

    .DESCRIPTION
    This adapter provides a testable boundary between the provider and AD cmdlets.
    Unit tests can inject a fake adapter without requiring a real AD environment.

    .PARAMETER Credential
    Optional PSCredential for AD operations. If not provided, uses integrated auth.
    
    .NOTES
    PSScriptAnalyzer suppression: This function intentionally uses ConvertTo-SecureString -AsPlainText
    as an explicit escape hatch for AccountPasswordAsPlainText. This is a documented design decision
    with automatic redaction via Copy-IdleRedactedObject.
    #>
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '', Justification = 'Intentional escape hatch for AccountPasswordAsPlainText with explicit opt-in and automatic redaction')]
    param(
        [Parameter()]
        [AllowNull()]
        [PSCredential] $Credential
    )

    $adapter = [pscustomobject]@{
        PSTypeName = 'IdLE.ADAdapter'
        Credential = $Credential
    }

    # Add LDAP filter escaping as a ScriptMethod to make it available in the adapter's scope
    # Uses 'Protect' prefix as 'Escape' is not an approved PowerShell verb
    $adapter | Add-Member -MemberType ScriptMethod -Name ProtectLdapFilterValue -Value {
        param(
            [Parameter(Mandatory)]
            [string] $Value
        )

        $escaped = $Value -replace '\\', '\5c'
        $escaped = $escaped -replace '\*', '\2a'
        $escaped = $escaped -replace '\(', '\28'
        $escaped = $escaped -replace '\)', '\29'
        $escaped = $escaped -replace "`0", '\00'
        return $escaped
    } -Force

    $adapter | Add-Member -MemberType ScriptMethod -Name GetUserByUpn -Value {
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $Upn
        )

        $escapedUpn = $this.ProtectLdapFilterValue($Upn)
        # Escape single quotes for PowerShell -Filter single-quoted string syntax by doubling them
        $escapedUpn = $escapedUpn -replace '''', ''''''
        $params = @{
            Filter     = "UserPrincipalName -eq '$escapedUpn'"
            Properties = @('Enabled', 'DistinguishedName', 'ObjectGuid', 'UserPrincipalName', 'sAMAccountName')
            ErrorAction = 'Stop'
        }
        if ($null -ne $this.Credential) {
            $params['Credential'] = $this.Credential
        }

        try {
            $user = Get-ADUser @params
            return $user
        }
        catch {
            return $null
        }
    } -Force

    $adapter | Add-Member -MemberType ScriptMethod -Name GetUserBySam -Value {
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $SamAccountName
        )

        $escapedSam = $this.ProtectLdapFilterValue($SamAccountName)
        # Escape single quotes for PowerShell -Filter single-quoted string syntax by doubling them
        $escapedSam = $escapedSam -replace '''', ''''''

        $params = @{
            Filter     = "sAMAccountName -eq '$escapedSam'"
            Properties = @('Enabled', 'DistinguishedName', 'ObjectGuid', 'UserPrincipalName', 'sAMAccountName')
            ErrorAction = 'Stop'
        }
        if ($null -ne $this.Credential) {
            $params['Credential'] = $this.Credential
        }

        try {
            $user = Get-ADUser @params
            return $user
        }
        catch {
            return $null
        }
    } -Force

    $adapter | Add-Member -MemberType ScriptMethod -Name GetUserByGuid -Value {
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $Guid
        )

        $params = @{
            Identity   = $Guid
            Properties = @('Enabled', 'DistinguishedName', 'ObjectGuid', 'UserPrincipalName', 'sAMAccountName')
            ErrorAction = 'Stop'
        }
        if ($null -ne $this.Credential) {
            $params['Credential'] = $this.Credential
        }

        try {
            $user = Get-ADUser @params
            return $user
        }
        catch {
            return $null
        }
    } -Force

    $adapter | Add-Member -MemberType ScriptMethod -Name NewUser -Value {
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $IdentityKey,

            [Parameter(Mandatory)]
            [ValidateNotNull()]
            [hashtable] $Attributes,

            [Parameter()]
            [bool] $Enabled = $true
        )

        # Classify IdentityKey: GUID, UPN, or SamAccountName-like
        $isGuid = $false
        $isUpn = $false
        $isSamAccountNameLike = $false

        $guid = [System.Guid]::Empty
        if ([System.Guid]::TryParse($IdentityKey, [ref]$guid)) {
            $isGuid = $true
        }
        elseif ($IdentityKey -match '@') {
            $isUpn = $true
        }
        else {
            $isSamAccountNameLike = $true
        }

        # 1. Derive SamAccountName from IdentityKey if missing
        $hasSamAccountName = $Attributes.ContainsKey('SamAccountName') -and -not [string]::IsNullOrWhiteSpace($Attributes['SamAccountName'])
        
        if (-not $hasSamAccountName) {
            if ($isSamAccountNameLike) {
                $Attributes['SamAccountName'] = $IdentityKey
                Write-Verbose "AD Provider: Derived SamAccountName='$IdentityKey' from IdentityKey (SamAccountName-like)"
            }
            elseif ($isUpn) {
                throw "SamAccountName is required when IdentityKey is a UPN. IdentityKey='$IdentityKey' appears to be a UPN (contains '@'). Please provide an explicit 'SamAccountName' in Attributes."
            }
            elseif ($isGuid) {
                throw "SamAccountName is required when IdentityKey is a GUID. IdentityKey='$IdentityKey' is a GUID. Please provide an explicit 'SamAccountName' in Attributes."
            }
        }

        # 2. Auto-set UserPrincipalName when IdentityKey is a UPN
        $hasUpn = $Attributes.ContainsKey('UserPrincipalName') -and -not [string]::IsNullOrWhiteSpace($Attributes['UserPrincipalName'])
        
        if (-not $hasUpn -and $isUpn) {
            $Attributes['UserPrincipalName'] = $IdentityKey
            Write-Verbose "AD Provider: Derived UserPrincipalName='$IdentityKey' from IdentityKey (UPN format)"
        }

        # 3. Derive CN/RDN Name with priority: Name > DisplayName > GivenName+Surname > IdentityKey
        $derivedName = $null
        $hasExplicitName = $Attributes.ContainsKey('Name') -and -not [string]::IsNullOrWhiteSpace($Attributes['Name'])
        
        if ($hasExplicitName) {
            $derivedName = $Attributes['Name']
            Write-Verbose "AD Provider: Using explicit Name='$derivedName' for CN/RDN"
        }
        elseif ($Attributes.ContainsKey('DisplayName') -and -not [string]::IsNullOrWhiteSpace($Attributes['DisplayName'])) {
            $derivedName = $Attributes['DisplayName']
            Write-Verbose "AD Provider: Derived CN/RDN Name='$derivedName' from DisplayName"
        }
        elseif ($Attributes.ContainsKey('GivenName') -and -not [string]::IsNullOrWhiteSpace($Attributes['GivenName']) -and 
                $Attributes.ContainsKey('Surname') -and -not [string]::IsNullOrWhiteSpace($Attributes['Surname'])) {
            $derivedName = "$($Attributes['GivenName']) $($Attributes['Surname'])"
            Write-Verbose "AD Provider: Derived CN/RDN Name='$derivedName' from GivenName+Surname"
        }
        else {
            $derivedName = $IdentityKey
            Write-Verbose "AD Provider: Falling back to IdentityKey='$derivedName' for CN/RDN Name (no DisplayName or GivenName+Surname provided)"
        }

        $params = @{
            Name        = $derivedName
            Enabled     = $Enabled
            ErrorAction = 'Stop'
        }

        if ($Attributes.ContainsKey('SamAccountName')) {
            $params['SamAccountName'] = $Attributes['SamAccountName']
        }
        if ($Attributes.ContainsKey('UserPrincipalName')) {
            $params['UserPrincipalName'] = $Attributes['UserPrincipalName']
        }
        if ($Attributes.ContainsKey('Path')) {
            $params['Path'] = $Attributes['Path']
        }
        if ($Attributes.ContainsKey('GivenName')) {
            $params['GivenName'] = $Attributes['GivenName']
        }
        if ($Attributes.ContainsKey('Surname')) {
            $params['Surname'] = $Attributes['Surname']
        }
        if ($Attributes.ContainsKey('DisplayName')) {
            $params['DisplayName'] = $Attributes['DisplayName']
        }
        if ($Attributes.ContainsKey('Description')) {
            $params['Description'] = $Attributes['Description']
        }
        if ($Attributes.ContainsKey('Department')) {
            $params['Department'] = $Attributes['Department']
        }
        if ($Attributes.ContainsKey('Title')) {
            $params['Title'] = $Attributes['Title']
        }
        if ($Attributes.ContainsKey('EmailAddress')) {
            $params['EmailAddress'] = $Attributes['EmailAddress']
        }

        # Password handling: support SecureString, ProtectedString, and explicit PlainText
        $hasAccountPassword = $Attributes.ContainsKey('AccountPassword')
        $hasAccountPasswordAsPlainText = $Attributes.ContainsKey('AccountPasswordAsPlainText')

        if ($hasAccountPassword -and $hasAccountPasswordAsPlainText) {
            throw "Ambiguous password configuration: both 'AccountPassword' and 'AccountPasswordAsPlainText' are provided. Use only one."
        }

        if ($hasAccountPassword) {
            $passwordValue = $Attributes['AccountPassword']

            if ($null -eq $passwordValue) {
                throw "AccountPassword: Value cannot be null. Provide a SecureString or ProtectedString (from ConvertFrom-SecureString)."
            }

            if ($passwordValue -is [securestring]) {
                # Mode 1: SecureString - use directly
                $params['AccountPassword'] = $passwordValue
            }
            elseif ($passwordValue -is [string]) {
                # Mode 2: ProtectedString (from ConvertFrom-SecureString)
                try {
                    $params['AccountPassword'] = ConvertTo-SecureString -String $passwordValue -ErrorAction Stop
                }
                catch {
                    $errorMsg = "AccountPassword: Expected a ProtectedString (output from ConvertFrom-SecureString without -Key) but conversion failed. "
                    $errorMsg += "Only DPAPI-scoped ProtectedStrings are supported (created under the same Windows user and machine). "
                    $errorMsg += "Key-based protected strings (using -Key or -SecureKey) are not supported. "
                    if ($null -ne $_.Exception) {
                        $errorMsg += "Exception type: $($PSItem.Exception.GetType().FullName). "
                        if (-not [string]::IsNullOrWhiteSpace($_.Exception.Message)) {
                            $errorMsg += "Message: $($_.Exception.Message)"
                        }
                    }
                    throw $errorMsg
                }
            }
            else {
                throw "AccountPassword: Expected a SecureString or ProtectedString (string from ConvertFrom-SecureString), but received type: $($passwordValue.GetType().FullName)"
            }
        }

        if ($hasAccountPasswordAsPlainText) {
            $plainTextPassword = $Attributes['AccountPasswordAsPlainText']

            if ($null -eq $plainTextPassword) {
                throw "AccountPasswordAsPlainText: Value cannot be null. Provide a non-empty plaintext password string."
            }

            if ($plainTextPassword -isnot [string]) {
                throw "AccountPasswordAsPlainText: Expected a string but received type: $($plainTextPassword.GetType().FullName)"
            }

            if ([string]::IsNullOrWhiteSpace($plainTextPassword)) {
                throw "AccountPasswordAsPlainText: Password cannot be null or empty."
            }

            # Mode 3: Explicit plaintext - convert with -AsPlainText
            # This is an intentional escape hatch with explicit opt-in via AccountPasswordAsPlainText.
            # The value is redacted from logs/events via Copy-IdleRedactedObject.
            $params['AccountPassword'] = ConvertTo-SecureString -String $plainTextPassword -AsPlainText -Force
        }

        if ($null -ne $this.Credential) {
            $params['Credential'] = $this.Credential
        }

        $user = New-ADUser @params -PassThru
        return $user
    } -Force

    $adapter | Add-Member -MemberType ScriptMethod -Name SetUser -Value {
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $Identity,

            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $AttributeName,

            [Parameter()]
            [AllowNull()]
            [object] $Value
        )

        $params = @{
            Identity    = $Identity
            ErrorAction = 'Stop'
        }

        if ($null -ne $this.Credential) {
            $params['Credential'] = $this.Credential
        }

        switch ($AttributeName) {
            'GivenName' { $params['GivenName'] = $Value }
            'Surname' { $params['Surname'] = $Value }
            'DisplayName' { $params['DisplayName'] = $Value }
            'Description' { $params['Description'] = $Value }
            'Department' { $params['Department'] = $Value }
            'Title' { $params['Title'] = $Value }
            'EmailAddress' { $params['EmailAddress'] = $Value }
            'UserPrincipalName' { $params['UserPrincipalName'] = $Value }
            default {
                $params['Replace'] = @{ $AttributeName = $Value }
            }
        }

        Set-ADUser @params
    } -Force

    $adapter | Add-Member -MemberType ScriptMethod -Name DisableUser -Value {
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $Identity
        )

        $params = @{
            Identity    = $Identity
            Enabled     = $false
            ErrorAction = 'Stop'
        }
        if ($null -ne $this.Credential) {
            $params['Credential'] = $this.Credential
        }

        Set-ADUser @params
    } -Force

    $adapter | Add-Member -MemberType ScriptMethod -Name EnableUser -Value {
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $Identity
        )

        $params = @{
            Identity    = $Identity
            Enabled     = $true
            ErrorAction = 'Stop'
        }
        if ($null -ne $this.Credential) {
            $params['Credential'] = $this.Credential
        }

        Set-ADUser @params
    } -Force

    $adapter | Add-Member -MemberType ScriptMethod -Name MoveObject -Value {
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $Identity,

            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $TargetPath
        )

        $params = @{
            Identity    = $Identity
            TargetPath  = $TargetPath
            ErrorAction = 'Stop'
        }
        if ($null -ne $this.Credential) {
            $params['Credential'] = $this.Credential
        }

        Move-ADObject @params
    } -Force

    $adapter | Add-Member -MemberType ScriptMethod -Name DeleteUser -Value {
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $Identity
        )

        $params = @{
            Identity    = $Identity
            Confirm     = $false
            ErrorAction = 'Stop'
        }
        if ($null -ne $this.Credential) {
            $params['Credential'] = $this.Credential
        }

        Remove-ADUser @params
    } -Force

    $adapter | Add-Member -MemberType ScriptMethod -Name GetGroupById -Value {
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $Identity
        )

        $params = @{
            Identity    = $Identity
            Properties  = @('DistinguishedName', 'Name', 'sAMAccountName', 'ObjectGuid')
            ErrorAction = 'Stop'
        }
        if ($null -ne $this.Credential) {
            $params['Credential'] = $this.Credential
        }

        try {
            $group = Get-ADGroup @params
            return $group
        }
        catch {
            return $null
        }
    } -Force

    $adapter | Add-Member -MemberType ScriptMethod -Name AddGroupMember -Value {
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $GroupIdentity,

            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $MemberIdentity
        )

        $params = @{
            Identity    = $GroupIdentity
            Members     = $MemberIdentity
            ErrorAction = 'Stop'
        }
        if ($null -ne $this.Credential) {
            $params['Credential'] = $this.Credential
        }

        Add-ADGroupMember @params
    } -Force

    $adapter | Add-Member -MemberType ScriptMethod -Name RemoveGroupMember -Value {
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $GroupIdentity,

            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $MemberIdentity
        )

        $params = @{
            Identity    = $GroupIdentity
            Members     = $MemberIdentity
            Confirm     = $false
            ErrorAction = 'Stop'
        }
        if ($null -ne $this.Credential) {
            $params['Credential'] = $this.Credential
        }

        Remove-ADGroupMember @params
    } -Force

    $adapter | Add-Member -MemberType ScriptMethod -Name GetUserGroups -Value {
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $Identity
        )

        $params = @{
            Identity    = $Identity
            ErrorAction = 'Stop'
        }
        if ($null -ne $this.Credential) {
            $params['Credential'] = $this.Credential
        }

        try {
            $groups = Get-ADPrincipalGroupMembership @params
            return $groups
        }
        catch {
            return @()
        }
    } -Force

    $adapter | Add-Member -MemberType ScriptMethod -Name ListUsers -Value {
        param(
            [Parameter()]
            [hashtable] $Filter
        )

        $filterString = '*'
        if ($null -ne $Filter -and $Filter.ContainsKey('Search') -and -not [string]::IsNullOrWhiteSpace($Filter['Search'])) {
            $searchValue = [string] $Filter['Search']
            $escapedSearch = $this.ProtectLdapFilterValue($searchValue)
            # Escape single quotes for use inside a single-quoted -Filter string (PowerShell/AD filter syntax)
            $filterSafeSearch = $escapedSearch -replace "'", "''"
            $filterString = "sAMAccountName -like '$filterSafeSearch*' -or UserPrincipalName -like '$filterSafeSearch*'"
        }

        $params = @{
            Filter      = $filterString
            Properties  = @('ObjectGuid', 'sAMAccountName', 'UserPrincipalName')
            ErrorAction = 'Stop'
        }
        if ($null -ne $this.Credential) {
            $params['Credential'] = $this.Credential
        }

        try {
            $users = Get-ADUser @params
            return $users
        }
        catch {
            return @()
        }
    } -Force

    return $adapter
}

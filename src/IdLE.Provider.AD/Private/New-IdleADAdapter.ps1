function New-IdleADAdapter {
    <#
    .SYNOPSIS
    Creates an internal adapter that wraps Active Directory cmdlets.

    .DESCRIPTION
    This adapter provides a testable boundary between the provider and AD cmdlets.
    Unit tests can inject a fake adapter without requiring a real AD environment.

    .PARAMETER Credential
    Optional PSCredential for AD operations. If not provided, uses integrated auth.
    #>
    [CmdletBinding()]
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
            [string] $Name,

            [Parameter(Mandatory)]
            [ValidateNotNull()]
            [hashtable] $Attributes,

            [Parameter()]
            [bool] $Enabled = $true
        )

        $params = @{
            Name        = $Name
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

function New-IdleExchangeOnlineAdapter {
    <#
    .SYNOPSIS
    Creates an internal adapter that wraps Exchange Online Management cmdlets.

    .DESCRIPTION
    This adapter provides a testable boundary between the provider and Exchange Online cmdlets.
    Unit tests can inject a fake adapter without requiring a real Exchange Online environment.

    The adapter wraps ExchangeOnlineManagement module cmdlets for maximum compatibility.

    .PARAMETER UseRestApi
    (Reserved for future use) Switch to indicate use of Graph API REST calls instead of cmdlets.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [switch] $UseRestApi
    )

    $adapter = [pscustomobject]@{
        PSTypeName = 'IdLE.ExchangeOnlineAdapter'
        UseRestApi = [bool]$UseRestApi
    }

    # Helper to safely invoke cmdlets with error handling
    $invokeSafely = {
        param(
            [Parameter(Mandatory)]
            [string] $CommandName,

            [Parameter()]
            [hashtable] $Parameters = @{}
        )

        # Regex patterns for sanitizing error messages (defined inside scriptblock for reliable scoping)
        $bearerTokenPattern = 'Bearer\s+[^\s]+'
        $tokenAssignmentPattern = 'token[^\s]*\s*=\s*[^\s,;]+'

        try {
            $result = & $CommandName @Parameters
            return $result
        }
        catch {
            # Build error message without exposing sensitive data
            $errorMessage = "Exchange Online command '$CommandName' failed"
            if ($_.Exception.Message) {
                # Sanitize error message to avoid leaking tokens/secrets
                $sanitized = $_.Exception.Message -replace $bearerTokenPattern, 'Bearer <REDACTED>'
                $sanitized = $sanitized -replace $tokenAssignmentPattern, 'token=<REDACTED>'
                $errorMessage += " | $sanitized"
            }

            $ex = [System.Exception]::new($errorMessage, $_.Exception)
            throw $ex
        }
    }

    $adapter | Add-Member -MemberType ScriptMethod -Name InvokeSafely -Value $invokeSafely -Force

    # GetMailbox: Retrieve mailbox details by identity (UPN or SMTP address)
    $adapter | Add-Member -MemberType ScriptMethod -Name GetMailbox -Value {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'AccessToken', Justification = 'Reserved for future Graph API integration')]
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $MailboxIdentity,

            [Parameter()]
            [AllowNull()]
            [string] $AccessToken
        )

        # AccessToken is reserved for future Graph API integration
        $null = $AccessToken

        try {
            $params = @{
                Identity    = $MailboxIdentity
                ErrorAction = 'Stop'
            }

            $mailbox = $this.InvokeSafely('Get-EXOMailbox', $params)

            if ($null -eq $mailbox) {
                return $null
            }

            # Normalize output to hashtable
            return @{
                Identity             = $mailbox.Identity
                PrimarySmtpAddress   = $mailbox.PrimarySmtpAddress
                UserPrincipalName    = $mailbox.UserPrincipalName
                DisplayName          = $mailbox.DisplayName
                RecipientType        = $mailbox.RecipientType
                RecipientTypeDetails = $mailbox.RecipientTypeDetails
                Guid                 = $mailbox.Guid
            }
        }
        catch {
            if ($_.Exception.Message -match 'couldn''t be found|not found|does not exist') {
                return $null
            }
            throw
        }
    } -Force

    # SetMailboxType: Convert mailbox type (User <-> Shared)
    $adapter | Add-Member -MemberType ScriptMethod -Name SetMailboxType -Value {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'AccessToken', Justification = 'Reserved for future Graph API integration')]
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $MailboxIdentity,

            [Parameter(Mandatory)]
            [ValidateSet('User', 'Shared', 'Room', 'Equipment')]
            [string] $Type,

            [Parameter()]
            [AllowNull()]
            [string] $AccessToken
        )

        # AccessToken is reserved for future Graph API integration
        $null = $AccessToken

        $params = @{
            Identity    = $MailboxIdentity
            ErrorAction = 'Stop'
        }

        # Map type to RecipientTypeDetails
        switch ($Type) {
            'User' {
                $params['Type'] = 'Regular'
            }
            'Shared' {
                $params['Type'] = 'Shared'
            }
            'Room' {
                $params['Type'] = 'Room'
            }
            'Equipment' {
                $params['Type'] = 'Equipment'
            }
        }

        $this.InvokeSafely('Set-Mailbox', $params)
    } -Force

    # GetMailboxAutoReplyConfiguration: Get Out of Office settings
    $adapter | Add-Member -MemberType ScriptMethod -Name GetMailboxAutoReplyConfiguration -Value {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'AccessToken', Justification = 'Reserved for future Graph API integration')]
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $MailboxIdentity,

            [Parameter()]
            [AllowNull()]
            [string] $AccessToken
        )

        # AccessToken is reserved for future Graph API integration
        $null = $AccessToken

        try {
            $params = @{
                Identity    = $MailboxIdentity
                ErrorAction = 'Stop'
            }

            $config = $this.InvokeSafely('Get-MailboxAutoReplyConfiguration', $params)

            if ($null -eq $config) {
                return $null
            }

            # Normalize output to hashtable
            return @{
                Identity                  = $config.Identity
                AutoReplyState            = $config.AutoReplyState
                StartTime                 = $config.StartTime
                EndTime                   = $config.EndTime
                InternalMessage           = $config.InternalMessage
                ExternalMessage           = $config.ExternalMessage
                ExternalAudience          = $config.ExternalAudience
                CreateOOFEvent            = $config.CreateOOFEvent
                OOFEventSubject           = $config.OOFEventSubject
                DeclineAllEventsForScheduledOOF = $config.DeclineAllEventsForScheduledOOF
            }
        }
        catch {
            if ($_.Exception.Message -match 'couldn''t be found|not found|does not exist') {
                return $null
            }
            throw
        }
    } -Force

    # SetMailboxAutoReplyConfiguration: Update Out of Office settings
    $adapter | Add-Member -MemberType ScriptMethod -Name SetMailboxAutoReplyConfiguration -Value {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'AccessToken', Justification = 'Reserved for future Graph API integration')]
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $MailboxIdentity,

            [Parameter(Mandatory)]
            [ValidateNotNull()]
            [hashtable] $Config,

            [Parameter()]
            [AllowNull()]
            [string] $AccessToken
        )

        # AccessToken is reserved for future Graph API integration
        $null = $AccessToken

        $params = @{
            Identity    = $MailboxIdentity
            ErrorAction = 'Stop'
        }

        # Map config keys to cmdlet parameters
        if ($Config.ContainsKey('Mode')) {
            $mode = $Config['Mode']
            switch ($mode) {
                'Disabled' { $params['AutoReplyState'] = 'Disabled' }
                'Enabled' { $params['AutoReplyState'] = 'Enabled' }
                'Scheduled' { $params['AutoReplyState'] = 'Scheduled' }
                default { throw "Invalid Mode value: $mode. Expected Disabled, Enabled, or Scheduled." }
            }
        }

        if ($Config.ContainsKey('Start')) {
            $params['StartTime'] = $Config['Start']
        }

        if ($Config.ContainsKey('End')) {
            $params['EndTime'] = $Config['End']
        }

        if ($Config.ContainsKey('InternalMessage')) {
            $params['InternalMessage'] = $Config['InternalMessage']
        }

        if ($Config.ContainsKey('ExternalMessage')) {
            $params['ExternalMessage'] = $Config['ExternalMessage']
        }

        if ($Config.ContainsKey('ExternalAudience')) {
            $params['ExternalAudience'] = $Config['ExternalAudience']
        }

        $this.InvokeSafely('Set-MailboxAutoReplyConfiguration', $params)
    } -Force

    # GetMailboxPermissions: Get FullAccess permissions for a mailbox
    $adapter | Add-Member -MemberType ScriptMethod -Name GetMailboxPermissions -Value {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'AccessToken', Justification = 'Reserved for future Graph API integration')]
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $MailboxIdentity,

            [Parameter()]
            [AllowNull()]
            [string] $AccessToken
        )

        # AccessToken is reserved for future Graph API integration
        $null = $AccessToken

        try {
            $params = @{
                Identity    = $MailboxIdentity
                ErrorAction = 'Stop'
            }

            $permissions = $this.InvokeSafely('Get-MailboxPermission', $params)

            if ($null -eq $permissions) {
                return @()
            }

            # Normalize output: filter out NT AUTHORITY, SELF, and SID-only entries.
            # - NT AUTHORITY\*: built-in system accounts (e.g. NT AUTHORITY\SELF from inheritance)
            # - *\SELF: owner self-permission added automatically by Exchange
            # - S-1-*: unresolved SIDs that should not be managed as named delegates
            $result = @()
            foreach ($perm in $permissions) {
                $user = [string]$perm.User
                if ($user -match '^NT AUTHORITY\\|\\SELF$|^S-1-') {
                    continue
                }
                foreach ($right in $perm.AccessRights) {
                    $result += @{
                        MailboxIdentity = $MailboxIdentity
                        User            = $user
                        AccessRight     = [string]$right
                        IsInherited     = [bool]$perm.IsInherited
                    }
                }
            }
            return $result
        }
        catch {
            if ($_.Exception.Message -match 'couldn''t be found|not found|does not exist') {
                return @()
            }
            throw
        }
    } -Force

    # AddMailboxPermission: Grant FullAccess to a mailbox
    $adapter | Add-Member -MemberType ScriptMethod -Name AddMailboxPermission -Value {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'AccessToken', Justification = 'Reserved for future Graph API integration')]
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $MailboxIdentity,

            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $User,

            [Parameter()]
            [AllowNull()]
            [string] $AccessToken
        )

        # AccessToken is reserved for future Graph API integration
        $null = $AccessToken

        $params = @{
            Identity     = $MailboxIdentity
            User         = $User
            AccessRights = 'FullAccess'
            ErrorAction  = 'Stop'
        }

        $this.InvokeSafely('Add-MailboxPermission', $params)
    } -Force

    # RemoveMailboxPermission: Revoke FullAccess from a mailbox
    $adapter | Add-Member -MemberType ScriptMethod -Name RemoveMailboxPermission -Value {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'AccessToken', Justification = 'Reserved for future Graph API integration')]
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $MailboxIdentity,

            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $User,

            [Parameter()]
            [AllowNull()]
            [string] $AccessToken
        )

        # AccessToken is reserved for future Graph API integration
        $null = $AccessToken

        $params = @{
            Identity     = $MailboxIdentity
            User         = $User
            AccessRights = 'FullAccess'
            Confirm      = $false
            ErrorAction  = 'Stop'
        }

        $this.InvokeSafely('Remove-MailboxPermission', $params)
    } -Force

    # GetRecipientPermissions: Get SendAs permissions for a mailbox
    $adapter | Add-Member -MemberType ScriptMethod -Name GetRecipientPermissions -Value {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'AccessToken', Justification = 'Reserved for future Graph API integration')]
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $MailboxIdentity,

            [Parameter()]
            [AllowNull()]
            [string] $AccessToken
        )

        # AccessToken is reserved for future Graph API integration
        $null = $AccessToken

        try {
            $params = @{
                Identity    = $MailboxIdentity
                ErrorAction = 'Stop'
            }

            $permissions = $this.InvokeSafely('Get-RecipientPermission', $params)

            if ($null -eq $permissions) {
                return @()
            }

            # Normalize output: filter out NT AUTHORITY entries.
            # Get-RecipientPermission only returns NT AUTHORITY\SELF for built-in system entries;
            # unlike Get-MailboxPermission it does not return unresolved SIDs or \SELF owner entries.
            $result = @()
            foreach ($perm in $permissions) {
                $trustee = [string]$perm.Trustee
                if ($trustee -match '^NT AUTHORITY\\') {
                    continue
                }
                $result += @{
                    MailboxIdentity = $MailboxIdentity
                    Trustee         = $trustee
                    AccessControlType = [string]$perm.AccessControlType
                    AccessRight     = [string]($perm.AccessRights -join ',')
                    IsInherited     = [bool]$perm.IsInherited
                }
            }
            return $result
        }
        catch {
            if ($_.Exception.Message -match 'couldn''t be found|not found|does not exist') {
                return @()
            }
            throw
        }
    } -Force

    # AddRecipientPermission: Grant SendAs to a mailbox
    $adapter | Add-Member -MemberType ScriptMethod -Name AddRecipientPermission -Value {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'AccessToken', Justification = 'Reserved for future Graph API integration')]
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $MailboxIdentity,

            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $Trustee,

            [Parameter()]
            [AllowNull()]
            [string] $AccessToken
        )

        # AccessToken is reserved for future Graph API integration
        $null = $AccessToken

        $params = @{
            Identity     = $MailboxIdentity
            Trustee      = $Trustee
            AccessRights = 'SendAs'
            Confirm      = $false
            ErrorAction  = 'Stop'
        }

        $this.InvokeSafely('Add-RecipientPermission', $params)
    } -Force

    # RemoveRecipientPermission: Revoke SendAs from a mailbox
    $adapter | Add-Member -MemberType ScriptMethod -Name RemoveRecipientPermission -Value {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'AccessToken', Justification = 'Reserved for future Graph API integration')]
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $MailboxIdentity,

            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $Trustee,

            [Parameter()]
            [AllowNull()]
            [string] $AccessToken
        )

        # AccessToken is reserved for future Graph API integration
        $null = $AccessToken

        $params = @{
            Identity     = $MailboxIdentity
            Trustee      = $Trustee
            AccessRights = 'SendAs'
            Confirm      = $false
            ErrorAction  = 'Stop'
        }

        $this.InvokeSafely('Remove-RecipientPermission', $params)
    } -Force

    # GetMailboxSendOnBehalf: Get the GrantSendOnBehalfTo list for a mailbox
    $adapter | Add-Member -MemberType ScriptMethod -Name GetMailboxSendOnBehalf -Value {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'AccessToken', Justification = 'Reserved for future Graph API integration')]
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $MailboxIdentity,

            [Parameter()]
            [AllowNull()]
            [string] $AccessToken
        )

        # AccessToken is reserved for future Graph API integration
        $null = $AccessToken

        try {
            $params = @{
                Identity    = $MailboxIdentity
                ErrorAction = 'Stop'
            }

            $mailbox = $this.InvokeSafely('Get-EXOMailbox', $params)

            if ($null -eq $mailbox) {
                return @()
            }

            # GrantSendOnBehalfTo returns a MultiValuedProperty - normalize to string array
            $result = @()
            foreach ($entry in $mailbox.GrantSendOnBehalfTo) {
                $result += [string]$entry
            }
            return $result
        }
        catch {
            if ($_.Exception.Message -match 'couldn''t be found|not found|does not exist') {
                return @()
            }
            throw
        }
    } -Force

    # SetMailboxSendOnBehalf: Set the GrantSendOnBehalfTo list for a mailbox
    $adapter | Add-Member -MemberType ScriptMethod -Name SetMailboxSendOnBehalf -Value {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'AccessToken', Justification = 'Reserved for future Graph API integration')]
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $MailboxIdentity,

            [Parameter(Mandatory)]
            [AllowEmptyCollection()]
            [string[]] $Delegates,

            [Parameter()]
            [AllowNull()]
            [string] $AccessToken
        )

        # AccessToken is reserved for future Graph API integration
        $null = $AccessToken

        $params = @{
            Identity              = $MailboxIdentity
            GrantSendOnBehalfTo   = $Delegates
            ErrorAction           = 'Stop'
        }

        $this.InvokeSafely('Set-Mailbox', $params)
    } -Force

    return $adapter
}

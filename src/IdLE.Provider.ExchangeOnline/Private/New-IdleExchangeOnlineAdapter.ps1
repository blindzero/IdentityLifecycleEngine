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

        try {
            $result = & $CommandName @Parameters
            return $result
        }
        catch {
            # Build error message without exposing sensitive data
            $errorMessage = "Exchange Online command '$CommandName' failed"
            if ($_.Exception.Message) {
                # Sanitize error message to avoid leaking tokens/secrets
                $sanitized = $_.Exception.Message -replace 'Bearer\s+[^\s]+', 'Bearer <REDACTED>'
                $sanitized = $sanitized -replace 'token[^\s]*\s*=\s*[^\s,;]+', 'token=<REDACTED>'
                $errorMessage += " | $sanitized"
            }

            $ex = [System.Exception]::new($errorMessage, $_.Exception)
            throw $ex
        }
    }

    $adapter | Add-Member -MemberType ScriptMethod -Name InvokeSafely -Value $invokeSafely -Force

    # GetMailbox: Retrieve mailbox details by identity (UPN or SMTP address)
    $adapter | Add-Member -MemberType ScriptMethod -Name GetMailbox -Value {
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $MailboxIdentity,

            [Parameter()]
            [AllowNull()]
            [string] $AccessToken
        )

        try {
            $params = @{
                Identity    = $MailboxIdentity
                ErrorAction = 'Stop'
            }

            $mailbox = $this.InvokeSafely('Get-Mailbox', $params)

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
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $MailboxIdentity,

            [Parameter()]
            [AllowNull()]
            [string] $AccessToken
        )

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

    return $adapter
}

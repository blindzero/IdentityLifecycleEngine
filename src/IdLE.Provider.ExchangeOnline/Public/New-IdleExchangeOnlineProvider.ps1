function New-IdleExchangeOnlineProvider {
    <#
    .SYNOPSIS
    Creates an Exchange Online mailbox provider for IdLE.

    .DESCRIPTION
    This provider integrates with Exchange Online for mailbox lifecycle management operations.
    It supports mailbox reporting, type conversions, and Out of Office configuration management.

    The provider implements the mailbox-specific provider contract used by IdLE.Steps.Mailbox.

    Identity addressing:
    - UserPrincipalName (UPN) - preferred
    - Primary SMTP address (email)
    - Mailbox GUID (for deterministic operations)

    The canonical identity key for all outputs is the primary SMTP address.

    Authentication:
    Provider methods accept an optional AuthSession parameter for runtime credential
    selection via the AuthSessionBroker. The provider supports multiple auth session formats:
    - String access token (for future Graph API integration)
    - Object with AccessToken property
    - Object with GetAccessToken() method
    - PSCredential (for certificate-based auth)

    By default, mailbox steps should use:
    - With.AuthSessionName = 'ExchangeOnline'
    - With.AuthSessionOptions = @{ Role = 'Admin' } (or other routing keys)

    Prerequisites:
    - ExchangeOnlineManagement PowerShell module must be installed
    - For app-only (certificate) auth: Windows platform required (MVP limitation)
    - Authenticated session must be established before using provider methods

    .PARAMETER Adapter
    Internal parameter for dependency injection during testing. Allows unit tests to inject
    a fake adapter without requiring a real Exchange Online environment.

    .EXAMPLE
    # Basic usage with delegated auth
    # Host establishes connection first
    Connect-ExchangeOnline -UserPrincipalName admin@contoso.com

    $provider = New-IdleExchangeOnlineProvider
    $plan = New-IdlePlan -WorkflowPath './workflow.psd1' -Request $request -Providers @{
        ExchangeOnline = $provider
    }

    .EXAMPLE
    # Certificate-based app-only auth (Windows only)
    # Host establishes connection first
    Connect-ExchangeOnline -CertificateThumbprint $thumbprint -AppId $appId -Organization $tenantId

    $provider = New-IdleExchangeOnlineProvider
    $plan = New-IdlePlan -WorkflowPath './workflow.psd1' -Request $request -Providers @{
        ExchangeOnline = $provider
    }

    .OUTPUTS
    PSCustomObject with IdLE mailbox provider contract methods

    .NOTES
    Requires Exchange Online Management module and appropriate permissions:
    - Exchange.ManageAsApp (app-only)
    - Exchange Administrator or Global Administrator role (delegated)
    - Required role: Mail Recipients (manage mailboxes)

    See the IdLE provider documentation for detailed setup.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object] $Adapter
    )

    if ($null -eq $Adapter) {
        # Verify ExchangeOnlineManagement module is available
        $module = Get-Module -Name 'ExchangeOnlineManagement' -ListAvailable -ErrorAction SilentlyContinue
        if ($null -eq $module) {
            throw "ExchangeOnlineManagement module is not installed. Install it with: Install-Module -Name ExchangeOnlineManagement -Scope CurrentUser"
        }

        $Adapter = New-IdleExchangeOnlineAdapter
    }

    $extractAccessToken = {
        param(
            [Parameter()]
            [AllowNull()]
            [object] $AuthSession
        )

        if ($null -eq $AuthSession) {
            # For tests/development, allow null but commands will use existing session
            return $null
        }

        # String token (for future Graph API integration)
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

        # PSCredential (for certificate-based auth)
        if ($AuthSession -is [PSCredential]) {
            # Certificate thumbprint might be in password field
            return $AuthSession.GetNetworkCredential().Password
        }

        # Default: allow null for existing session-based commands
        return $null
    }

    $normalizeMailboxType = {
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $RecipientTypeDetails
        )

        # Map Exchange RecipientTypeDetails to simplified types
        switch -Regex ($RecipientTypeDetails) {
            '^UserMailbox$|^LinkedMailbox$|^RemoteUserMailbox$' { return 'User' }
            '^SharedMailbox$|^RemoteSharedMailbox$' { return 'Shared' }
            '^RoomMailbox$|^RemoteRoomMailbox$' { return 'Room' }
            '^EquipmentMailbox$|^RemoteEquipmentMailbox$' { return 'Equipment' }
            default { return $RecipientTypeDetails }
        }
    }

    $provider = [pscustomobject]@{
        PSTypeName = 'IdLE.Provider.ExchangeOnlineProvider'
        Name       = 'ExchangeOnlineProvider'
        Adapter    = $Adapter
    }

    $provider | Add-Member -MemberType ScriptMethod -Name ExtractAccessToken -Value $extractAccessToken -Force
    $provider | Add-Member -MemberType ScriptMethod -Name NormalizeMailboxType -Value $normalizeMailboxType -Force

    $provider | Add-Member -MemberType ScriptMethod -Name GetCapabilities -Value {
        $caps = @(
            'IdLE.Mailbox.Read'
            'IdLE.Mailbox.Type.Ensure'
            'IdLE.Mailbox.OutOfOffice.Ensure'
        )

        return $caps
    } -Force

    # GetMailbox: Retrieve mailbox details
    $provider | Add-Member -MemberType ScriptMethod -Name GetMailbox -Value {
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $IdentityKey,

            [Parameter()]
            [AllowNull()]
            [object] $AuthSession
        )

        $accessToken = $this.ExtractAccessToken($AuthSession)

        $mailbox = $this.Adapter.GetMailbox($IdentityKey, $accessToken)

        if ($null -eq $mailbox) {
            throw "Mailbox '$IdentityKey' not found."
        }

        # Normalize mailbox type
        $normalizedType = $this.NormalizeMailboxType($mailbox['RecipientTypeDetails'])

        # Return structured mailbox data
        return [pscustomobject]@{
            PSTypeName           = 'IdLE.Mailbox'
            IdentityKey          = [string]$mailbox['PrimarySmtpAddress']
            PrimarySmtpAddress   = [string]$mailbox['PrimarySmtpAddress']
            UserPrincipalName    = [string]$mailbox['UserPrincipalName']
            DisplayName          = [string]$mailbox['DisplayName']
            Type                 = $normalizedType
            RecipientType        = [string]$mailbox['RecipientType']
            RecipientTypeDetails = [string]$mailbox['RecipientTypeDetails']
            Guid                 = [string]$mailbox['Guid']
        }
    } -Force

    # EnsureMailboxType: Idempotent mailbox type conversion
    $provider | Add-Member -MemberType ScriptMethod -Name EnsureMailboxType -Value {
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $IdentityKey,

            [Parameter(Mandatory)]
            [ValidateSet('User', 'Shared', 'Room', 'Equipment')]
            [string] $DesiredType,

            [Parameter()]
            [AllowNull()]
            [object] $AuthSession
        )

        $accessToken = $this.ExtractAccessToken($AuthSession)

        # Get current mailbox state
        $mailbox = $this.GetMailbox($IdentityKey, $AuthSession)
        $currentType = $mailbox.Type

        # Check idempotency
        if ($currentType -eq $DesiredType) {
            return [pscustomobject]@{
                PSTypeName  = 'IdLE.ProviderResult'
                Operation   = 'EnsureMailboxType'
                IdentityKey = $mailbox.PrimarySmtpAddress
                Changed     = $false
                Type        = $DesiredType
            }
        }

        # Perform conversion
        $this.Adapter.SetMailboxType($mailbox.PrimarySmtpAddress, $DesiredType, $accessToken)

        return [pscustomobject]@{
            PSTypeName  = 'IdLE.ProviderResult'
            Operation   = 'EnsureMailboxType'
            IdentityKey = $mailbox.PrimarySmtpAddress
            Changed     = $true
            Type        = $DesiredType
        }
    } -Force

    # GetOutOfOffice: Retrieve Out of Office configuration
    $provider | Add-Member -MemberType ScriptMethod -Name GetOutOfOffice -Value {
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $IdentityKey,

            [Parameter()]
            [AllowNull()]
            [object] $AuthSession
        )

        $accessToken = $this.ExtractAccessToken($AuthSession)

        # Verify mailbox exists first
        $mailbox = $this.GetMailbox($IdentityKey, $AuthSession)

        $config = $this.Adapter.GetMailboxAutoReplyConfiguration($mailbox.PrimarySmtpAddress, $accessToken)

        if ($null -eq $config) {
            throw "Out of Office configuration for mailbox '$IdentityKey' not found."
        }

        # Map AutoReplyState to simplified Mode
        $mode = switch ($config['AutoReplyState']) {
            'Disabled' { 'Disabled' }
            'Enabled' { 'Enabled' }
            'Scheduled' { 'Scheduled' }
            default { 'Disabled' }
        }

        return [pscustomobject]@{
            PSTypeName       = 'IdLE.MailboxOutOfOffice'
            IdentityKey      = $mailbox.PrimarySmtpAddress
            Mode             = $mode
            Start            = $config['StartTime']
            End              = $config['EndTime']
            InternalMessage  = $config['InternalMessage']
            ExternalMessage  = $config['ExternalMessage']
            ExternalAudience = $config['ExternalAudience']
        }
    } -Force

    # EnsureOutOfOffice: Idempotent Out of Office configuration
    $provider | Add-Member -MemberType ScriptMethod -Name EnsureOutOfOffice -Value {
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $IdentityKey,

            [Parameter(Mandatory)]
            [ValidateNotNull()]
            [hashtable] $Config,

            [Parameter()]
            [AllowNull()]
            [object] $AuthSession
        )

        $accessToken = $this.ExtractAccessToken($AuthSession)

        # Validate Config shape
        if (-not $Config.ContainsKey('Mode')) {
            throw "OutOfOffice Config must contain 'Mode' key (Disabled, Enabled, or Scheduled)."
        }

        $mode = $Config['Mode']
        if ($mode -notin @('Disabled', 'Enabled', 'Scheduled')) {
            throw "OutOfOffice Config Mode must be 'Disabled', 'Enabled', or 'Scheduled'. Got: $mode"
        }

        if ($mode -eq 'Scheduled') {
            if (-not $Config.ContainsKey('Start') -or -not $Config.ContainsKey('End')) {
                throw "OutOfOffice Config Mode 'Scheduled' requires 'Start' and 'End' keys."
            }
        }

        # Verify mailbox exists first
        $mailbox = $this.GetMailbox($IdentityKey, $AuthSession)

        # Get current config for idempotency check
        $currentConfig = $this.GetOutOfOffice($mailbox.PrimarySmtpAddress, $AuthSession)

        # Simple idempotency check: if mode matches and messages match, skip update
        $changed = $false
        if ($currentConfig.Mode -ne $mode) {
            $changed = $true
        }
        elseif ($Config.ContainsKey('InternalMessage') -and $currentConfig.InternalMessage -ne $Config['InternalMessage']) {
            $changed = $true
        }
        elseif ($Config.ContainsKey('ExternalMessage') -and $currentConfig.ExternalMessage -ne $Config['ExternalMessage']) {
            $changed = $true
        }
        elseif ($Config.ContainsKey('ExternalAudience') -and $currentConfig.ExternalAudience -ne $Config['ExternalAudience']) {
            $changed = $true
        }
        elseif ($mode -eq 'Scheduled') {
            # Compare dates (allow small tolerance for serialization differences)
            # Tolerance: 60 seconds to account for rounding during serialization/deserialization
            $dateComparisonToleranceSeconds = 60
            $startDiff = [Math]::Abs(($currentConfig.Start - [DateTime]$Config['Start']).TotalSeconds)
            $endDiff = [Math]::Abs(($currentConfig.End - [DateTime]$Config['End']).TotalSeconds)
            if ($startDiff -gt $dateComparisonToleranceSeconds -or $endDiff -gt $dateComparisonToleranceSeconds) {
                $changed = $true
            }
        }

        if (-not $changed) {
            return [pscustomobject]@{
                PSTypeName  = 'IdLE.ProviderResult'
                Operation   = 'EnsureOutOfOffice'
                IdentityKey = $mailbox.PrimarySmtpAddress
                Changed     = $false
            }
        }

        # Perform update
        $this.Adapter.SetMailboxAutoReplyConfiguration($mailbox.PrimarySmtpAddress, $Config, $accessToken)

        return [pscustomobject]@{
            PSTypeName  = 'IdLE.ProviderResult'
            Operation   = 'EnsureOutOfOffice'
            IdentityKey = $mailbox.PrimarySmtpAddress
            Changed     = $true
        }
    } -Force

    return $provider
}

Set-StrictMode -Version Latest

BeforeDiscovery {
    . (Join-Path -Path $PSScriptRoot -ChildPath '..\_testHelpers.ps1')
    Import-IdleTestModule
}

Describe 'ExchangeOnline provider - Unit tests' {
    BeforeAll {
        $testsRoot = Split-Path -Path $PSScriptRoot -Parent
        $repoRoot = Split-Path -Path $testsRoot -Parent
        $modulePath = Join-Path -Path $repoRoot -ChildPath 'src\IdLE.Provider.ExchangeOnline\IdLE.Provider.ExchangeOnline.psm1'
        if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf)) {
            throw "ExchangeOnline provider module not found at: $modulePath"
        }
        Import-Module $modulePath -Force

        Mock -ModuleName 'IdLE.Provider.ExchangeOnline' -CommandName Test-IdleExchangeOnlinePrerequisites -MockWith {
            [pscustomobject]@{
                PSTypeName      = 'IdLE.PrerequisitesResult'
                IsHealthy       = $true
                MissingRequired = @()
                Notes           = @()
            }
        }

        # Create a fake adapter for tests
        $fakeAdapter = [pscustomobject]@{
            PSTypeName = 'IdLE.ExchangeOnlineAdapter.Fake'
            Store      = @{
                Mailboxes     = @{}
                AutoReply     = @{}
                FullAccess    = @{}   # mailboxSmtp -> @{ userLower -> $true }
                SendAs        = @{}   # mailboxSmtp -> @{ trusteeLower -> $true }
                SendOnBehalf  = @{}   # mailboxSmtp -> [List[string]]
            }
        }

        # GetMailbox: Retrieve mailbox by identity
        $fakeAdapter | Add-Member -MemberType ScriptMethod -Name GetMailbox -Value {
            param($MailboxIdentity, $AccessToken)
            
            # Try direct key lookup
            if ($this.Store.Mailboxes.ContainsKey($MailboxIdentity)) {
                return $this.Store.Mailboxes[$MailboxIdentity]
            }
            
            # Search by UPN or SMTP
            foreach ($key in $this.Store.Mailboxes.Keys) {
                $mailbox = $this.Store.Mailboxes[$key]
                if ($mailbox['UserPrincipalName'] -eq $MailboxIdentity -or
                    $mailbox['PrimarySmtpAddress'] -eq $MailboxIdentity) {
                    return $mailbox
                }
            }
            
            return $null
        } -Force

        # SetMailboxType: Convert mailbox type
        $fakeAdapter | Add-Member -MemberType ScriptMethod -Name SetMailboxType -Value {
            param($MailboxIdentity, $Type, $AccessToken)
            
            $mailbox = $this.GetMailbox($MailboxIdentity, $AccessToken)
            if ($null -eq $mailbox) {
                throw "Mailbox '$MailboxIdentity' not found."
            }
            
            # Update RecipientTypeDetails based on Type
            $mailbox['RecipientTypeDetails'] = switch ($Type) {
                'User' { 'UserMailbox' }
                'Shared' { 'SharedMailbox' }
                'Room' { 'RoomMailbox' }
                'Equipment' { 'EquipmentMailbox' }
                default { 'UserMailbox' }
            }
        } -Force

        # GetMailboxAutoReplyConfiguration: Get OOF settings
        $fakeAdapter | Add-Member -MemberType ScriptMethod -Name GetMailboxAutoReplyConfiguration -Value {
            param($MailboxIdentity, $AccessToken)
            
            $key = $MailboxIdentity
            if (-not $this.Store.AutoReply.ContainsKey($key)) {
                # Initialize default OOF config
                $this.Store.AutoReply[$key] = @{
                    Identity         = $MailboxIdentity
                    AutoReplyState   = 'Disabled'
                    StartTime        = $null
                    EndTime          = $null
                    InternalMessage  = ''
                    ExternalMessage  = ''
                    ExternalAudience = 'All'
                }
            }
            return $this.Store.AutoReply[$key]
        } -Force

        # SetMailboxAutoReplyConfiguration: Update OOF settings
        $fakeAdapter | Add-Member -MemberType ScriptMethod -Name SetMailboxAutoReplyConfiguration -Value {
            param($MailboxIdentity, $Config, $AccessToken)
            
            $key = $MailboxIdentity
            if (-not $this.Store.AutoReply.ContainsKey($key)) {
                $this.Store.AutoReply[$key] = @{
                    Identity         = $MailboxIdentity
                    AutoReplyState   = 'Disabled'
                    StartTime        = $null
                    EndTime          = $null
                    InternalMessage  = ''
                    ExternalMessage  = ''
                    ExternalAudience = 'All'
                }
            }
            
            $current = $this.Store.AutoReply[$key]
            
            # Map Mode to AutoReplyState (same as real adapter)
            if ($Config.ContainsKey('Mode')) {
                $mode = $Config['Mode']
                switch ($mode) {
                    'Disabled' { $current['AutoReplyState'] = 'Disabled' }
                    'Enabled' { $current['AutoReplyState'] = 'Enabled' }
                    'Scheduled' { $current['AutoReplyState'] = 'Scheduled' }
                }
            }
            if ($Config.ContainsKey('AutoReplyState')) {
                $current['AutoReplyState'] = $Config['AutoReplyState']
            }
            if ($Config.ContainsKey('Start')) {
                $current['StartTime'] = $Config['Start']
            }
            if ($Config.ContainsKey('StartTime')) {
                $current['StartTime'] = $Config['StartTime']
            }
            if ($Config.ContainsKey('End')) {
                $current['EndTime'] = $Config['End']
            }
            if ($Config.ContainsKey('EndTime')) {
                $current['EndTime'] = $Config['EndTime']
            }
            if ($Config.ContainsKey('InternalMessage')) {
                $current['InternalMessage'] = $Config['InternalMessage']
            }
            if ($Config.ContainsKey('ExternalMessage')) {
                $current['ExternalMessage'] = $Config['ExternalMessage']
            }
            if ($Config.ContainsKey('ExternalAudience')) {
                $current['ExternalAudience'] = $Config['ExternalAudience']
            }
        } -Force

        # Helper to create test mailboxes
        function Add-TestMailbox {
            param(
                [string]$PrimarySmtpAddress,
                [string]$UserPrincipalName = $PrimarySmtpAddress,
                [string]$DisplayName = "User Mailbox",
                [string]$RecipientTypeDetails = 'UserMailbox',
                [string]$RecipientType = 'UserMailbox'
            )
            
            $guid = [System.Guid]::NewGuid().ToString()
            $mailbox = @{
                Identity             = $PrimarySmtpAddress
                PrimarySmtpAddress   = $PrimarySmtpAddress
                UserPrincipalName    = $UserPrincipalName
                DisplayName          = $DisplayName
                RecipientType        = $RecipientType
                RecipientTypeDetails = $RecipientTypeDetails
                Guid                 = $guid
            }
            
            $fakeAdapter.Store.Mailboxes[$PrimarySmtpAddress] = $mailbox
            return $mailbox
        }

        # GetMailboxPermissions: return FullAccess entries for a mailbox
        $fakeAdapter | Add-Member -MemberType ScriptMethod -Name GetMailboxPermissions -Value {
            param($MailboxIdentity, $AccessToken)

            $key = $MailboxIdentity.ToLowerInvariant()
            if (-not $this.Store.FullAccess.ContainsKey($key)) {
                return @()
            }
            $result = @()
            foreach ($user in $this.Store.FullAccess[$key].Keys) {
                $result += @{
                    MailboxIdentity = $MailboxIdentity
                    User            = $user
                    AccessRight     = 'FullAccess'
                    IsInherited     = $false
                }
            }
            return $result
        } -Force

        # AddMailboxPermission: grant FullAccess
        $fakeAdapter | Add-Member -MemberType ScriptMethod -Name AddMailboxPermission -Value {
            param($MailboxIdentity, $User, $AccessToken)

            $key = $MailboxIdentity.ToLowerInvariant()
            if (-not $this.Store.FullAccess.ContainsKey($key)) {
                $this.Store.FullAccess[$key] = @{}
            }
            $this.Store.FullAccess[$key][$User.ToLowerInvariant()] = $true
        } -Force

        # RemoveMailboxPermission: revoke FullAccess
        $fakeAdapter | Add-Member -MemberType ScriptMethod -Name RemoveMailboxPermission -Value {
            param($MailboxIdentity, $User, $AccessToken)

            $key = $MailboxIdentity.ToLowerInvariant()
            if ($this.Store.FullAccess.ContainsKey($key)) {
                $this.Store.FullAccess[$key].Remove($User.ToLowerInvariant())
            }
        } -Force

        # GetRecipientPermissions: return SendAs entries for a mailbox
        $fakeAdapter | Add-Member -MemberType ScriptMethod -Name GetRecipientPermissions -Value {
            param($MailboxIdentity, $AccessToken)

            $key = $MailboxIdentity.ToLowerInvariant()
            if (-not $this.Store.SendAs.ContainsKey($key)) {
                return @()
            }
            $result = @()
            foreach ($trustee in $this.Store.SendAs[$key].Keys) {
                $result += @{
                    MailboxIdentity   = $MailboxIdentity
                    Trustee           = $trustee
                    AccessControlType = 'Allow'
                    AccessRight       = 'SendAs'
                    IsInherited       = $false
                }
            }
            return $result
        } -Force

        # AddRecipientPermission: grant SendAs
        $fakeAdapter | Add-Member -MemberType ScriptMethod -Name AddRecipientPermission -Value {
            param($MailboxIdentity, $Trustee, $AccessToken)

            $key = $MailboxIdentity.ToLowerInvariant()
            if (-not $this.Store.SendAs.ContainsKey($key)) {
                $this.Store.SendAs[$key] = @{}
            }
            $this.Store.SendAs[$key][$Trustee.ToLowerInvariant()] = $true
        } -Force

        # RemoveRecipientPermission: revoke SendAs
        $fakeAdapter | Add-Member -MemberType ScriptMethod -Name RemoveRecipientPermission -Value {
            param($MailboxIdentity, $Trustee, $AccessToken)

            $key = $MailboxIdentity.ToLowerInvariant()
            if ($this.Store.SendAs.ContainsKey($key)) {
                $this.Store.SendAs[$key].Remove($Trustee.ToLowerInvariant())
            }
        } -Force

        # GetMailboxSendOnBehalf: return SendOnBehalf delegate list
        $fakeAdapter | Add-Member -MemberType ScriptMethod -Name GetMailboxSendOnBehalf -Value {
            param($MailboxIdentity, $AccessToken)

            $key = $MailboxIdentity.ToLowerInvariant()
            if (-not $this.Store.SendOnBehalf.ContainsKey($key)) {
                return @()
            }
            return @($this.Store.SendOnBehalf[$key])
        } -Force

        # SetMailboxSendOnBehalf: replace SendOnBehalf delegate list
        $fakeAdapter | Add-Member -MemberType ScriptMethod -Name SetMailboxSendOnBehalf -Value {
            param($MailboxIdentity, $Delegates, $AccessToken)

            $key = $MailboxIdentity.ToLowerInvariant()
            $list = [System.Collections.Generic.List[string]]::new()
            foreach ($d in $Delegates) { $list.Add($d) }
            $this.Store.SendOnBehalf[$key] = $list
        } -Force

        # Create provider with fake adapter
        $provider = New-IdleExchangeOnlineProvider -Adapter $fakeAdapter
    }

    Context 'GetCapabilities' {
        It 'returns mailbox-specific capabilities' {
            $caps = $provider.GetCapabilities()
            $caps | Should -Contain 'IdLE.Mailbox.Info.Read'
            $caps | Should -Contain 'IdLE.Mailbox.Type.Ensure'
            $caps | Should -Contain 'IdLE.Mailbox.OutOfOffice.Ensure'
            $caps | Should -Contain 'IdLE.Mailbox.Permissions.Ensure'
        }
    }

    Context 'GetMailbox' {
        It 'retrieves mailbox by primary SMTP address' {
            Add-TestMailbox -PrimarySmtpAddress 'user1@contoso.com' -DisplayName 'User One'
            
            $mailbox = $provider.GetMailbox('user1@contoso.com', $null)
            
            $mailbox | Should -Not -BeNullOrEmpty
            $mailbox.PrimarySmtpAddress | Should -Be 'user1@contoso.com'
            $mailbox.DisplayName | Should -Be 'User One'
            $mailbox.Type | Should -Be 'User'
        }

        It 'throws error when mailbox not found' {
            { $provider.GetMailbox('nonexistent@contoso.com', $null) } |
                Should -Throw "*Mailbox 'nonexistent@contoso.com' not found*"
        }

        It 'normalizes mailbox type correctly' {
            Add-TestMailbox -PrimarySmtpAddress 'shared1@contoso.com' -RecipientTypeDetails 'SharedMailbox'
            
            $mailbox = $provider.GetMailbox('shared1@contoso.com', $null)
            
            $mailbox.Type | Should -Be 'Shared'
            $mailbox.RecipientTypeDetails | Should -Be 'SharedMailbox'
        }
    }

    Context 'EnsureMailboxType' {
        It 'converts user mailbox to shared mailbox' {
            Add-TestMailbox -PrimarySmtpAddress 'user2@contoso.com' -RecipientTypeDetails 'UserMailbox'
            
            $result = $provider.EnsureMailboxType('user2@contoso.com', 'Shared', $null)
            
            $result.Changed | Should -Be $true
            $result.Operation | Should -Be 'EnsureMailboxType'
            $result.Type | Should -Be 'Shared'
            
            # Verify mailbox was actually updated
            $mailbox = $provider.GetMailbox('user2@contoso.com', $null)
            $mailbox.Type | Should -Be 'Shared'
        }

        It 'is idempotent when mailbox already has desired type' {
            Add-TestMailbox -PrimarySmtpAddress 'shared2@contoso.com' -RecipientTypeDetails 'SharedMailbox'
            
            $result = $provider.EnsureMailboxType('shared2@contoso.com', 'Shared', $null)
            
            $result.Changed | Should -Be $false
        }

        It 'supports all mailbox types' {
            foreach ($type in @('Shared', 'Room', 'Equipment', 'User')) {
                $email = "test-$type@contoso.com".ToLowerInvariant()
                # Always start with UserMailbox, except for last iteration testing User type
                $startType = if ($type -eq 'User') { 'SharedMailbox' } else { 'UserMailbox' }
                Add-TestMailbox -PrimarySmtpAddress $email -RecipientTypeDetails $startType
                
                $result = $provider.EnsureMailboxType($email, $type, $null)
                
                $result.Changed | Should -Be $true
                $result.Type | Should -Be $type
            }
        }
    }

    Context 'GetOutOfOffice' {
        It 'retrieves Out of Office configuration' {
            Add-TestMailbox -PrimarySmtpAddress 'user3@contoso.com'
            
            $config = $provider.GetOutOfOffice('user3@contoso.com', $null)
            
            $config | Should -Not -BeNullOrEmpty
            $config.Mode | Should -Be 'Disabled'
            $config.IdentityKey | Should -Be 'user3@contoso.com'
        }

        It 'throws error when mailbox not found' {
            { $provider.GetOutOfOffice('nonexistent@contoso.com', $null) } |
                Should -Throw "*Mailbox 'nonexistent@contoso.com' not found*"
        }
    }

    Context 'EnsureOutOfOffice' {
        It 'enables Out of Office' {
            Add-TestMailbox -PrimarySmtpAddress 'user4@contoso.com'
            
            $config = @{
                Mode            = 'Enabled'
                InternalMessage = 'I am out of office.'
                ExternalMessage = 'Currently unavailable.'
            }
            
            $result = $provider.EnsureOutOfOffice('user4@contoso.com', $config, $null)
            
            $result.Changed | Should -Be $true
            $result.Operation | Should -Be 'EnsureOutOfOffice'
            
            # Verify OOF was actually updated
            $oofConfig = $provider.GetOutOfOffice('user4@contoso.com', $null)
            $oofConfig.Mode | Should -Be 'Enabled'
            $oofConfig.InternalMessage | Should -Be 'I am out of office.'
        }

        It 'is idempotent when OOF already matches desired state' {
            Add-TestMailbox -PrimarySmtpAddress 'user5@contoso.com'
            
            $config = @{
                Mode            = 'Enabled'
                InternalMessage = 'Out of office'
            }
            
            # Set initial state
            $provider.EnsureOutOfOffice('user5@contoso.com', $config, $null) | Out-Null
            
            # Second call should report no change
            $result = $provider.EnsureOutOfOffice('user5@contoso.com', $config, $null)
            $result.Changed | Should -Be $false
        }

        It 'configures scheduled Out of Office' {
            Add-TestMailbox -PrimarySmtpAddress 'user6@contoso.com'
            
            $start = [DateTime]::Parse('2025-02-01T00:00:00Z')
            $end = [DateTime]::Parse('2025-02-15T00:00:00Z')
            
            $config = @{
                Mode  = 'Scheduled'
                Start = $start
                End   = $end
                InternalMessage = 'On vacation'
            }
            
            $result = $provider.EnsureOutOfOffice('user6@contoso.com', $config, $null)
            
            $result.Changed | Should -Be $true
            
            # Verify OOF was updated
            $oofConfig = $provider.GetOutOfOffice('user6@contoso.com', $null)
            $oofConfig.Mode | Should -Be 'Scheduled'
        }

        It 'disables Out of Office' {
            Add-TestMailbox -PrimarySmtpAddress 'user7@contoso.com'
            
            # First enable it
            $enableConfig = @{ Mode = 'Enabled'; InternalMessage = 'Away' }
            $provider.EnsureOutOfOffice('user7@contoso.com', $enableConfig, $null) | Out-Null
            
            # Now disable it
            $disableConfig = @{ Mode = 'Disabled' }
            $result = $provider.EnsureOutOfOffice('user7@contoso.com', $disableConfig, $null)
            
            $result.Changed | Should -Be $true
            
            # Verify OOF is disabled
            $oofConfig = $provider.GetOutOfOffice('user7@contoso.com', $null)
            $oofConfig.Mode | Should -Be 'Disabled'
        }

        It 'throws error when Config is missing Mode' {
            Add-TestMailbox -PrimarySmtpAddress 'user8@contoso.com'
            
            $badConfig = @{ InternalMessage = 'Test' }
            
            { $provider.EnsureOutOfOffice('user8@contoso.com', $badConfig, $null) } |
                Should -Throw -ExpectedMessage "*must contain 'Mode' key*"
        }

        It 'throws error when Scheduled mode is missing Start/End' {
            Add-TestMailbox -PrimarySmtpAddress 'user9@contoso.com'
            
            $badConfig = @{ Mode = 'Scheduled' }
            
            { $provider.EnsureOutOfOffice('user9@contoso.com', $badConfig, $null) } |
                Should -Throw -ExpectedMessage "*requires 'Start' and 'End' keys*"
        }

        It 'throws error when Mode is invalid' {
            Add-TestMailbox -PrimarySmtpAddress 'user10@contoso.com'
            
            $badConfig = @{ Mode = 'InvalidMode' }
            
            { $provider.EnsureOutOfOffice('user10@contoso.com', $badConfig, $null) } |
                Should -Throw -ExpectedMessage "*must be 'Disabled', 'Enabled', or 'Scheduled'*"
        }

        It 'detects changes to ExternalAudience and updates accordingly' {
            Add-TestMailbox -PrimarySmtpAddress 'user11@contoso.com'
            
            # Set initial OOF with ExternalAudience = 'Known'
            $initialConfig = @{
                Mode             = 'Enabled'
                InternalMessage  = 'Out of office'
                ExternalMessage  = 'Currently unavailable'
                ExternalAudience = 'Known'
            }
            $provider.EnsureOutOfOffice('user11@contoso.com', $initialConfig, $null) | Out-Null
            
            # Change only ExternalAudience to 'All', keep messages the same
            $updatedConfig = @{
                Mode             = 'Enabled'
                InternalMessage  = 'Out of office'
                ExternalMessage  = 'Currently unavailable'
                ExternalAudience = 'All'
            }
            $result = $provider.EnsureOutOfOffice('user11@contoso.com', $updatedConfig, $null)
            
            # Should detect the change and update
            $result.Changed | Should -Be $true
            
            # Verify ExternalAudience was actually updated
            $oofConfig = $provider.GetOutOfOffice('user11@contoso.com', $null)
            $oofConfig.ExternalAudience | Should -Be 'All'
        }

        It 'handles HTML normalization for stable idempotency' {
            Add-TestMailbox -PrimarySmtpAddress 'user12@contoso.com'
            
            # Set initial OOF with plain HTML message
            $initialConfig = @{
                Mode            = 'Enabled'
                InternalMessage = '<p>Out of office</p>'
                ExternalMessage = 'Currently unavailable'
            }
            $provider.EnsureOutOfOffice('user12@contoso.com', $initialConfig, $null) | Out-Null
            
            # Simulate Exchange wrapping the message in HTML/body tags
            $wrappedMessage = "<html><head></head><body>`r`n<p>Out of office</p>`r`n</body></html>"
            $fakeAdapter.Store.AutoReply['user12@contoso.com']['InternalMessage'] = $wrappedMessage
            
            # Re-run with same logical message (should be idempotent)
            $result = $provider.EnsureOutOfOffice('user12@contoso.com', $initialConfig, $null)
            
            # Should detect no change despite server-side wrapping
            $result.Changed | Should -Be $false
        }

        It 'handles line ending normalization for stable idempotency' {
            Add-TestMailbox -PrimarySmtpAddress 'user13@contoso.com'
            
            # Set initial OOF with LF line endings
            $messageWithLF = "Line 1`nLine 2`nLine 3"
            $initialConfig = @{
                Mode            = 'Enabled'
                InternalMessage = $messageWithLF
            }
            $provider.EnsureOutOfOffice('user13@contoso.com', $initialConfig, $null) | Out-Null
            
            # Simulate Exchange returning CRLF line endings
            $messageWithCRLF = "Line 1`r`nLine 2`r`nLine 3"
            $fakeAdapter.Store.AutoReply['user13@contoso.com']['InternalMessage'] = $messageWithCRLF
            
            # Re-run with LF message (should be idempotent)
            $result = $provider.EnsureOutOfOffice('user13@contoso.com', $initialConfig, $null)
            
            # Should detect no change despite line ending differences
            $result.Changed | Should -Be $false
        }
    }

    Context 'New-IdleExchangeOnlineAdapter - InvokeSafely scoping regression' {
        BeforeAll {
            # Import private adapter function directly for unit testing
            $repoRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
            $adapterPath = Join-Path -Path $repoRoot -ChildPath 'src\IdLE.Provider.ExchangeOnline\Private\New-IdleExchangeOnlineAdapter.ps1'

            if (-not (Test-Path -LiteralPath $adapterPath)) {
                throw "Private adapter function file not found at path: $adapterPath"
            }
            . $adapterPath

            # Dot-source provider test helpers so Invoke-IdleTestBearerTokenError is available at run time
            . (Join-Path -Path $PSScriptRoot -ChildPath '_testHelpers.Providers.ps1')
        }

        It 'InvokeSafely can be called from another ScriptMethod without variable-not-set error' {
            # Regression test: $bearerTokenPattern and $tokenAssignmentPattern must be in scope
            # when InvokeSafely is invoked via $this.InvokeSafely() from another ScriptMethod.
            $adapter = New-IdleExchangeOnlineAdapter

            # Wrap the real adapter with a ScriptMethod that calls $this.InvokeSafely() to
            # simulate the same execution path as GetMailbox -> InvokeSafely.
            $adapter | Add-Member -MemberType ScriptMethod -Name TestViaMethod -Value {
                $this.InvokeSafely('Write-Output', @{ InputObject = 'ok' })
            } -Force

            { $adapter.TestViaMethod() } | Should -Not -Throw
        }

        It 'InvokeSafely sanitizes bearer tokens in error messages without variable-not-set error' {
            $adapter = New-IdleExchangeOnlineAdapter

            $adapter | Add-Member -MemberType ScriptMethod -Name TestErrorSanitization -Value {
                $this.InvokeSafely('Invoke-IdleTestBearerTokenError', @{})
            } -Force

            { $adapter.TestErrorSanitization() } | Should -Throw -ExpectedMessage "*Bearer <REDACTED>*"
        }
    }

    Context 'Normalize-IdleExchangeOnlineAutoReplyMessage' {
        BeforeAll {
            # Import the private normalization function for direct testing
            $repoRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
            $normalizeFunctionPath = Join-Path -Path $repoRoot -ChildPath 'src\IdLE.Provider.ExchangeOnline\Private\Normalize-IdleExchangeOnlineAutoReplyMessage.ps1'
            
            if (-not (Test-Path -LiteralPath $normalizeFunctionPath -PathType Leaf)) {
                throw "Normalize-IdleExchangeOnlineAutoReplyMessage script not found at: $normalizeFunctionPath"
            }
            
            # Dot-source the private function
            . $normalizeFunctionPath
        }
        
        It 'removes HTML wrappers' {
            $input = '<html><head></head><body><p>Test message</p></body></html>'
            $normalized = Normalize-IdleExchangeOnlineAutoReplyMessage -Message $input
            
            $normalized | Should -Be '<p>Test message</p>'
        }

        It 'normalizes CRLF to LF' {
            $input = "Line 1`r`nLine 2`r`nLine 3"
            $normalized = Normalize-IdleExchangeOnlineAutoReplyMessage -Message $input
            
            $normalized | Should -Be "Line 1`nLine 2`nLine 3"
        }

        It 'trims leading and trailing whitespace' {
            $input = "   <p>Test message</p>   `n`n"
            $normalized = Normalize-IdleExchangeOnlineAutoReplyMessage -Message $input
            
            $normalized | Should -Be '<p>Test message</p>'
        }

        It 'normalizes excessive spaces conservatively' {
            $input = '<p>Test    message     here</p>'
            $normalized = Normalize-IdleExchangeOnlineAutoReplyMessage -Message $input
            
            # 3+ spaces become 2 spaces (conservative normalization)
            $normalized | Should -Be '<p>Test  message  here</p>'
        }

        It 'handles empty string input' {
            $normalized = Normalize-IdleExchangeOnlineAutoReplyMessage -Message ''
            
            $normalized | Should -Be ''
        }

        It 'handles null input' {
            $normalized = Normalize-IdleExchangeOnlineAutoReplyMessage -Message $null
            
            $normalized | Should -Be ''
        }

        It 'removes DOCTYPE declarations' {
            $input = '<!DOCTYPE html><html><body><p>Test</p></body></html>'
            $normalized = Normalize-IdleExchangeOnlineAutoReplyMessage -Message $input
            
            $normalized | Should -Be '<p>Test</p>'
        }

        It 'preserves intentional HTML formatting' {
            $input = '<p>This is <strong>important</strong> and <a href="mailto:test@example.com">contact us</a>.</p>'
            $normalized = Normalize-IdleExchangeOnlineAutoReplyMessage -Message $input
            
            $normalized | Should -Be '<p>This is <strong>important</strong> and <a href="mailto:test@example.com">contact us</a>.</p>'
        }
    }

    Context 'EnsureMailboxPermissions' {
        It 'grants FullAccess and reports Changed = true' {
            Add-TestMailbox -PrimarySmtpAddress 'perm1@contoso.com'

            $permissions = @(
                @{ AssignedUser = 'delegate1@contoso.com'; Right = 'FullAccess'; Ensure = 'Present' }
            )

            $result = $provider.EnsureMailboxPermissions('perm1@contoso.com', $permissions, $null)

            $result.Changed | Should -Be $true
            $result.Operation | Should -Be 'EnsureMailboxPermissions'

            # Verify the permission was stored
            $fakeAdapter.Store.FullAccess['perm1@contoso.com']['delegate1@contoso.com'] | Should -Be $true
        }

        It 'is idempotent when FullAccess already present' {
            Add-TestMailbox -PrimarySmtpAddress 'perm2@contoso.com'
            $fakeAdapter.Store.FullAccess['perm2@contoso.com'] = @{ 'delegate1@contoso.com' = $true }

            $permissions = @(
                @{ AssignedUser = 'delegate1@contoso.com'; Right = 'FullAccess'; Ensure = 'Present' }
            )

            $result = $provider.EnsureMailboxPermissions('perm2@contoso.com', $permissions, $null)

            $result.Changed | Should -Be $false
        }

        It 'revokes FullAccess when Ensure = Absent' {
            Add-TestMailbox -PrimarySmtpAddress 'perm3@contoso.com'
            $fakeAdapter.Store.FullAccess['perm3@contoso.com'] = @{ 'delegate1@contoso.com' = $true }

            $permissions = @(
                @{ AssignedUser = 'delegate1@contoso.com'; Right = 'FullAccess'; Ensure = 'Absent' }
            )

            $result = $provider.EnsureMailboxPermissions('perm3@contoso.com', $permissions, $null)

            $result.Changed | Should -Be $true
            $fakeAdapter.Store.FullAccess['perm3@contoso.com'].ContainsKey('delegate1@contoso.com') | Should -Be $false
        }

        It 'grants SendAs and reports Changed = true' {
            Add-TestMailbox -PrimarySmtpAddress 'perm4@contoso.com'

            $permissions = @(
                @{ AssignedUser = 'delegate2@contoso.com'; Right = 'SendAs'; Ensure = 'Present' }
            )

            $result = $provider.EnsureMailboxPermissions('perm4@contoso.com', $permissions, $null)

            $result.Changed | Should -Be $true
            $fakeAdapter.Store.SendAs['perm4@contoso.com']['delegate2@contoso.com'] | Should -Be $true
        }

        It 'is idempotent when SendAs already present' {
            Add-TestMailbox -PrimarySmtpAddress 'perm5@contoso.com'
            $fakeAdapter.Store.SendAs['perm5@contoso.com'] = @{ 'delegate2@contoso.com' = $true }

            $permissions = @(
                @{ AssignedUser = 'delegate2@contoso.com'; Right = 'SendAs'; Ensure = 'Present' }
            )

            $result = $provider.EnsureMailboxPermissions('perm5@contoso.com', $permissions, $null)

            $result.Changed | Should -Be $false
        }

        It 'revokes SendAs when Ensure = Absent' {
            Add-TestMailbox -PrimarySmtpAddress 'perm6@contoso.com'
            $fakeAdapter.Store.SendAs['perm6@contoso.com'] = @{ 'delegate2@contoso.com' = $true }

            $permissions = @(
                @{ AssignedUser = 'delegate2@contoso.com'; Right = 'SendAs'; Ensure = 'Absent' }
            )

            $result = $provider.EnsureMailboxPermissions('perm6@contoso.com', $permissions, $null)

            $result.Changed | Should -Be $true
            $fakeAdapter.Store.SendAs['perm6@contoso.com'].ContainsKey('delegate2@contoso.com') | Should -Be $false
        }

        It 'grants SendOnBehalf and reports Changed = true' {
            Add-TestMailbox -PrimarySmtpAddress 'perm7@contoso.com'

            $permissions = @(
                @{ AssignedUser = 'delegate3@contoso.com'; Right = 'SendOnBehalf'; Ensure = 'Present' }
            )

            $result = $provider.EnsureMailboxPermissions('perm7@contoso.com', $permissions, $null)

            $result.Changed | Should -Be $true
            $fakeAdapter.Store.SendOnBehalf['perm7@contoso.com'] | Should -Contain 'delegate3@contoso.com'
        }

        It 'is idempotent when SendOnBehalf already present' {
            Add-TestMailbox -PrimarySmtpAddress 'perm8@contoso.com'
            $list = [System.Collections.Generic.List[string]]::new()
            $list.Add('delegate3@contoso.com')
            $fakeAdapter.Store.SendOnBehalf['perm8@contoso.com'] = $list

            $permissions = @(
                @{ AssignedUser = 'delegate3@contoso.com'; Right = 'SendOnBehalf'; Ensure = 'Present' }
            )

            $result = $provider.EnsureMailboxPermissions('perm8@contoso.com', $permissions, $null)

            $result.Changed | Should -Be $false
        }

        It 'revokes SendOnBehalf when Ensure = Absent' {
            Add-TestMailbox -PrimarySmtpAddress 'perm9@contoso.com'
            $list = [System.Collections.Generic.List[string]]::new()
            $list.Add('delegate3@contoso.com')
            $fakeAdapter.Store.SendOnBehalf['perm9@contoso.com'] = $list

            $permissions = @(
                @{ AssignedUser = 'delegate3@contoso.com'; Right = 'SendOnBehalf'; Ensure = 'Absent' }
            )

            $result = $provider.EnsureMailboxPermissions('perm9@contoso.com', $permissions, $null)

            $result.Changed | Should -Be $true
            $fakeAdapter.Store.SendOnBehalf['perm9@contoso.com'] | Should -Not -Contain 'delegate3@contoso.com'
        }

        It 'handles mixed rights in a single call' {
            Add-TestMailbox -PrimarySmtpAddress 'perm10@contoso.com'

            $permissions = @(
                @{ AssignedUser = 'userA@contoso.com'; Right = 'FullAccess';   Ensure = 'Present' }
                @{ AssignedUser = 'userB@contoso.com'; Right = 'SendAs';       Ensure = 'Present' }
                @{ AssignedUser = 'userC@contoso.com'; Right = 'SendOnBehalf'; Ensure = 'Present' }
            )

            $result = $provider.EnsureMailboxPermissions('perm10@contoso.com', $permissions, $null)

            $result.Changed | Should -Be $true
            $fakeAdapter.Store.FullAccess['perm10@contoso.com']['usera@contoso.com']  | Should -Be $true
            $fakeAdapter.Store.SendAs['perm10@contoso.com']['userb@contoso.com']      | Should -Be $true
            $fakeAdapter.Store.SendOnBehalf['perm10@contoso.com']                      | Should -Contain 'userC@contoso.com'
        }

        It 'throws error when mailbox not found' {
            $permissions = @(
                @{ AssignedUser = 'delegate1@contoso.com'; Right = 'FullAccess'; Ensure = 'Present' }
            )

            { $provider.EnsureMailboxPermissions('nonexistent@contoso.com', $permissions, $null) } |
                Should -Throw "*Mailbox 'nonexistent@contoso.com' not found*"
        }

        It 'emits Evaluated and Result events when EventSink is set' {
            Add-TestMailbox -PrimarySmtpAddress 'evt1@contoso.com'

            $capturedEvents = [System.Collections.Generic.List[hashtable]]::new()
            $fakeEventSink = [pscustomobject]@{}
            $fakeEventSink | Add-Member -MemberType ScriptMethod -Name WriteEvent -Value {
                param($Type, $Message, $StepName, $Data)
                $script:capturedEvents.Add(@{ Type = $Type; Message = $Message; Data = $Data })
            } -Force

            $provider.EventSink = $fakeEventSink
            $script:capturedEvents = $capturedEvents

            $permissions = @(
                @{ AssignedUser = 'delegate1@contoso.com'; Right = 'FullAccess'; Ensure = 'Present' }
            )

            $result = $provider.EnsureMailboxPermissions('evt1@contoso.com', $permissions, $null)

            $provider.EventSink = $null

            $evalEvents = @($capturedEvents | Where-Object { $_.Type -eq 'Provider.ExchangeOnline.Permissions.Evaluated' })
            $applyEvents = @($capturedEvents | Where-Object { $_.Type -eq 'Provider.ExchangeOnline.Permissions.Applying' })
            $resultEvents = @($capturedEvents | Where-Object { $_.Type -eq 'Provider.ExchangeOnline.Permissions.Result' })

            $evalEvents.Count | Should -BeGreaterOrEqual 1
            $applyEvents.Count | Should -Be 1
            $resultEvents.Count | Should -Be 1
            $result.Changed | Should -Be $true
        }

        It 'does not emit events when EventSink is null' {
            Add-TestMailbox -PrimarySmtpAddress 'evt2@contoso.com'

            $provider.EventSink = $null

            $permissions = @(
                @{ AssignedUser = 'delegate1@contoso.com'; Right = 'FullAccess'; Ensure = 'Present' }
            )

            # Should not throw even with no EventSink
            { $provider.EnsureMailboxPermissions('evt2@contoso.com', $permissions, $null) } | Should -Not -Throw
        }
    }

    Context 'InvokeSafely transient error marking' {
        BeforeAll {
            $testsRoot = Split-Path -Path $PSScriptRoot -Parent
            $repoRoot = Split-Path -Path $testsRoot -Parent
            $adapterPath = Join-Path -Path $repoRoot -ChildPath 'src\IdLE.Provider.ExchangeOnline\Private\New-IdleExchangeOnlineAdapter.ps1'
            . $adapterPath

            # Dot-source provider helpers so EXO simulation functions are in scope for ScriptMethods
            . (Join-Path -Path $PSScriptRoot -ChildPath '_testHelpers.Providers.ps1')

            # Load Test-IdleTransientError for recursive exception chain checking
            $retryHelpersPath = Join-Path -Path $repoRoot -ChildPath 'src\IdLE.Core\Private\Invoke-IdleWithRetry.ps1'
            . $retryHelpersPath
        }

        It 'marks server-side EXO error as transient (detectable by retry engine)' {
            $testAdapter = New-IdleExchangeOnlineAdapter

            $caught = $null
            try {
                $testAdapter.InvokeSafely('Invoke-IdleEXOSimulateServerSideError', @{})
            }
            catch {
                $caught = $_.Exception
            }

            $caught | Should -Not -BeNullOrEmpty
            # Use Test-IdleTransientError (same check as the plan executor's Invoke-IdleWithRetry)
            Test-IdleTransientError -Exception $caught | Should -Be $true
        }

        It 'marks throttling EXO error as transient (detectable by retry engine)' {
            $testAdapter = New-IdleExchangeOnlineAdapter

            $caught = $null
            try {
                $testAdapter.InvokeSafely('Invoke-IdleEXOSimulateThrottleError', @{})
            }
            catch {
                $caught = $_.Exception
            }

            $caught | Should -Not -BeNullOrEmpty
            Test-IdleTransientError -Exception $caught | Should -Be $true
        }

        It 'does not mark non-transient EXO error as transient' {
            $testAdapter = New-IdleExchangeOnlineAdapter

            $caught = $null
            try {
                $testAdapter.InvokeSafely('Invoke-IdleEXOSimulatePermError', @{})
            }
            catch {
                $caught = $_.Exception
            }

            $caught | Should -Not -BeNullOrEmpty
            Test-IdleTransientError -Exception $caught | Should -Be $false
        }
    }

    Context 'Transient error propagation from EnsureMailboxPermissions' {
        BeforeAll {
            $testsRoot = Split-Path -Path $PSScriptRoot -Parent
            $repoRoot = Split-Path -Path $testsRoot -Parent
            $retryHelpersPath = Join-Path -Path $repoRoot -ChildPath 'src\IdLE.Core\Private\Invoke-IdleWithRetry.ps1'
            . $retryHelpersPath
        }

        It 'propagates transient exception from Remove operation so plan executor can retry the step' {
            Add-TestMailbox -PrimarySmtpAddress 'transient1@contoso.com'
            $fakeAdapter.Store.FullAccess['transient1@contoso.com'] = @{ 'delegate1@contoso.com' = $true }

            # Simulate what the real InvokeSafely does when EXO returns a server-side error
            $fakeAdapter | Add-Member -MemberType ScriptMethod -Name RemoveMailboxPermission -Value {
                param($MailboxIdentity, $User, $AccessToken)
                $inner = [System.Exception]::new('A server side error has occurred.')
                $wrapped = [System.Exception]::new("Exchange Online command 'Remove-MailboxPermission' failed | A server side error has occurred.", $inner)
                $wrapped.Data['Idle.IsTransient'] = $true
                throw $wrapped
            } -Force

            $caught = $null
            try {
                $provider.EnsureMailboxPermissions('transient1@contoso.com', @(
                    @{ AssignedUser = 'delegate1@contoso.com'; Right = 'FullAccess'; Ensure = 'Absent' }
                ), $null)
            }
            catch {
                $caught = $_.Exception
            }

            # Restore original RemoveMailboxPermission
            $fakeAdapter | Add-Member -MemberType ScriptMethod -Name RemoveMailboxPermission -Value {
                param($MailboxIdentity, $User, $AccessToken)
                $key = $MailboxIdentity.ToLowerInvariant()
                if ($this.Store.FullAccess.ContainsKey($key)) {
                    $this.Store.FullAccess[$key].Remove($User.ToLowerInvariant())
                }
            } -Force

            $caught | Should -Not -BeNullOrEmpty
            # Use Test-IdleTransientError (same check as the plan executor's Invoke-IdleWithRetry)
            Test-IdleTransientError -Exception $caught | Should -Be $true
        }
    }
}

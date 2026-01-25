Set-StrictMode -Version Latest

BeforeDiscovery {
    . (Join-Path -Path $PSScriptRoot -ChildPath '..\_testHelpers.ps1')
    Import-IdleTestModule

    $testsRoot = Split-Path -Path $PSScriptRoot -Parent
    $repoRoot = Split-Path -Path $testsRoot -Parent

    # Import ExchangeOnline provider
    $exoModulePath = Join-Path -Path $repoRoot -ChildPath 'src\IdLE.Provider.ExchangeOnline\IdLE.Provider.ExchangeOnline.psm1'
    if (-not (Test-Path -LiteralPath $exoModulePath -PathType Leaf)) {
        throw "ExchangeOnline provider module not found at: $exoModulePath"
    }
    Import-Module $exoModulePath -Force
}

Describe 'ExchangeOnline provider - Unit tests' {
    BeforeAll {
        # Create a fake adapter for tests
        $fakeAdapter = [pscustomobject]@{
            PSTypeName = 'IdLE.ExchangeOnlineAdapter.Fake'
            Store      = @{
                Mailboxes = @{}
                AutoReply = @{}
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

        # Create provider with fake adapter
        $provider = New-IdleExchangeOnlineProvider -Adapter $fakeAdapter
    }

    Context 'GetCapabilities' {
        It 'returns mailbox-specific capabilities' {
            $caps = $provider.GetCapabilities()
            $caps | Should -Contain 'IdLE.Mailbox.Info.Read'
            $caps | Should -Contain 'IdLE.Mailbox.Type.Ensure'
            $caps | Should -Contain 'IdLE.Mailbox.OutOfOffice.Ensure'
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
    }
}

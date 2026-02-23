Set-StrictMode -Version Latest

BeforeAll {
    . (Join-Path (Split-Path -Path $PSScriptRoot -Parent) '_testHelpers.ps1')
    Import-IdleTestModule
    Import-IdleTestMailboxModule

    # Import Mailbox step pack
    $testsRoot = $PSScriptRoot
    $repoRoot = Split-Path -Path $testsRoot -Parent
    $mailboxModulePath = Join-Path -Path $repoRoot -ChildPath 'src\IdLE.Steps.Mailbox\IdLE.Steps.Mailbox.psm1'
    if (Test-Path -LiteralPath $mailboxModulePath -PathType Leaf) {
        Import-Module $mailboxModulePath -Force
    }
}

Describe 'Invoke-IdleStepMailboxPermissionsEnsure' {
    BeforeEach {
        # Create mock ExchangeOnline provider with in-memory permission store
        $script:Provider = [pscustomobject]@{
            PSTypeName = 'Mock.ExchangeOnlineProvider'
            Store      = @{
                FullAccess    = @{}   # mailboxSmtp -> @{ userLower -> $true }
                SendAs        = @{}   # mailboxSmtp -> @{ trusteeLower -> $true }
                SendOnBehalf  = @{}   # mailboxSmtp -> [List[string]]
            }
        }

        $script:Provider | Add-Member -MemberType ScriptMethod -Name EnsureMailboxPermissions -Value {
            param($IdentityKey, $Permissions, $AuthSession)

            $smtpKey = $IdentityKey.ToLowerInvariant()

            # Ensure store keys exist
            if (-not $this.Store.FullAccess.ContainsKey($smtpKey))   { $this.Store.FullAccess[$smtpKey]   = @{} }
            if (-not $this.Store.SendAs.ContainsKey($smtpKey))       { $this.Store.SendAs[$smtpKey]       = @{} }
            if (-not $this.Store.SendOnBehalf.ContainsKey($smtpKey)) {
                $this.Store.SendOnBehalf[$smtpKey] = [System.Collections.Generic.List[string]]::new()
            }

            $changed = $false

            foreach ($entry in $Permissions) {
                $userLower = ([string]$entry.AssignedUser).ToLowerInvariant()

                switch ($entry.Right) {
                    'FullAccess' {
                        $isPresent = $this.Store.FullAccess[$smtpKey].ContainsKey($userLower)
                        if ($entry.Ensure -eq 'Present' -and -not $isPresent) {
                            $this.Store.FullAccess[$smtpKey][$userLower] = $true
                            $changed = $true
                        }
                        elseif ($entry.Ensure -eq 'Absent' -and $isPresent) {
                            $this.Store.FullAccess[$smtpKey].Remove($userLower)
                            $changed = $true
                        }
                    }
                    'SendAs' {
                        $isPresent = $this.Store.SendAs[$smtpKey].ContainsKey($userLower)
                        if ($entry.Ensure -eq 'Present' -and -not $isPresent) {
                            $this.Store.SendAs[$smtpKey][$userLower] = $true
                            $changed = $true
                        }
                        elseif ($entry.Ensure -eq 'Absent' -and $isPresent) {
                            $this.Store.SendAs[$smtpKey].Remove($userLower)
                            $changed = $true
                        }
                    }
                    'SendOnBehalf' {
                        $list = $this.Store.SendOnBehalf[$smtpKey]
                        $isPresent = $list | Where-Object { $_.ToLowerInvariant() -eq $userLower }
                        if ($entry.Ensure -eq 'Present' -and -not $isPresent) {
                            $list.Add([string]$entry.AssignedUser)
                            $changed = $true
                        }
                        elseif ($entry.Ensure -eq 'Absent' -and $isPresent) {
                            $toRemove = @($list | Where-Object { $_.ToLowerInvariant() -eq $userLower })
                            foreach ($r in $toRemove) { $list.Remove($r) | Out-Null }
                            $changed = $true
                        }
                    }
                }
            }

            return [pscustomobject]@{
                PSTypeName  = 'IdLE.ProviderResult'
                Operation   = 'EnsureMailboxPermissions'
                IdentityKey = $IdentityKey
                Changed     = $changed
            }
        } -Force

        $script:Context = [pscustomobject]@{
            PSTypeName = 'IdLE.ExecutionContext'
            Plan       = $null
            Providers  = @{ ExchangeOnline = $script:Provider }
            EventSink  = [pscustomobject]@{ WriteEvent = { param($Type, $Message, $StepName, $Data) } }
        }

        $script:Context | Add-Member -MemberType ScriptMethod -Name AcquireAuthSession -Value {
            param($Name, $Options)
            return 'mock-token'
        } -Force

        $script:StepTemplate = [pscustomobject]@{
            Name = 'Ensure Mailbox Permissions'
            Type = 'IdLE.Step.Mailbox.EnsurePermissions'
            With = @{
                Provider    = 'ExchangeOnline'
                IdentityKey = 'shared@contoso.com'
                Permissions = @(
                    @{ AssignedUser = 'user1@contoso.com'; Right = 'FullAccess'; Ensure = 'Present' }
                )
            }
        }
    }

    Context 'Behavior' {
        It 'grants FullAccess and reports Changed = true' {
            $handler = 'IdLE.Steps.Mailbox\Invoke-IdleStepMailboxPermissionsEnsure'
            $result = & $handler -Context $script:Context -Step $script:StepTemplate

            $result.Status | Should -Be 'Completed'
            $result.Changed | Should -Be $true

            $script:Provider.Store.FullAccess['shared@contoso.com']['user1@contoso.com'] | Should -Be $true
        }

        It 'is idempotent when FullAccess already present' {
            # Pre-populate the store
            $script:Provider.Store.FullAccess['shared@contoso.com'] = @{ 'user1@contoso.com' = $true }

            $handler = 'IdLE.Steps.Mailbox\Invoke-IdleStepMailboxPermissionsEnsure'
            $result = & $handler -Context $script:Context -Step $script:StepTemplate

            $result.Status | Should -Be 'Completed'
            $result.Changed | Should -Be $false
        }

        It 'revokes FullAccess when Ensure = Absent' {
            $script:Provider.Store.FullAccess['shared@contoso.com'] = @{ 'user1@contoso.com' = $true }

            $step = [pscustomobject]@{
                Name = 'Revoke FullAccess'
                Type = 'IdLE.Step.Mailbox.EnsurePermissions'
                With = @{
                    Provider    = 'ExchangeOnline'
                    IdentityKey = 'shared@contoso.com'
                    Permissions = @(
                        @{ AssignedUser = 'user1@contoso.com'; Right = 'FullAccess'; Ensure = 'Absent' }
                    )
                }
            }

            $handler = 'IdLE.Steps.Mailbox\Invoke-IdleStepMailboxPermissionsEnsure'
            $result = & $handler -Context $script:Context -Step $step

            $result.Status | Should -Be 'Completed'
            $result.Changed | Should -Be $true
            $script:Provider.Store.FullAccess['shared@contoso.com'].ContainsKey('user1@contoso.com') | Should -Be $false
        }

        It 'is idempotent when Absent is already absent' {
            $step = [pscustomobject]@{
                Name = 'Revoke SendAs (already absent)'
                Type = 'IdLE.Step.Mailbox.EnsurePermissions'
                With = @{
                    Provider    = 'ExchangeOnline'
                    IdentityKey = 'shared@contoso.com'
                    Permissions = @(
                        @{ AssignedUser = 'user2@contoso.com'; Right = 'SendAs'; Ensure = 'Absent' }
                    )
                }
            }

            $handler = 'IdLE.Steps.Mailbox\Invoke-IdleStepMailboxPermissionsEnsure'
            $result = & $handler -Context $script:Context -Step $step

            $result.Status | Should -Be 'Completed'
            $result.Changed | Should -Be $false
        }

        It 'grants SendAs and reports Changed = true' {
            $step = [pscustomobject]@{
                Name = 'Grant SendAs'
                Type = 'IdLE.Step.Mailbox.EnsurePermissions'
                With = @{
                    Provider    = 'ExchangeOnline'
                    IdentityKey = 'shared@contoso.com'
                    Permissions = @(
                        @{ AssignedUser = 'user2@contoso.com'; Right = 'SendAs'; Ensure = 'Present' }
                    )
                }
            }

            $handler = 'IdLE.Steps.Mailbox\Invoke-IdleStepMailboxPermissionsEnsure'
            $result = & $handler -Context $script:Context -Step $step

            $result.Status | Should -Be 'Completed'
            $result.Changed | Should -Be $true
            $script:Provider.Store.SendAs['shared@contoso.com']['user2@contoso.com'] | Should -Be $true
        }

        It 'grants SendOnBehalf and reports Changed = true' {
            $step = [pscustomobject]@{
                Name = 'Grant SendOnBehalf'
                Type = 'IdLE.Step.Mailbox.EnsurePermissions'
                With = @{
                    Provider    = 'ExchangeOnline'
                    IdentityKey = 'shared@contoso.com'
                    Permissions = @(
                        @{ AssignedUser = 'user3@contoso.com'; Right = 'SendOnBehalf'; Ensure = 'Present' }
                    )
                }
            }

            $handler = 'IdLE.Steps.Mailbox\Invoke-IdleStepMailboxPermissionsEnsure'
            $result = & $handler -Context $script:Context -Step $step

            $result.Status | Should -Be 'Completed'
            $result.Changed | Should -Be $true
            $script:Provider.Store.SendOnBehalf['shared@contoso.com'] | Should -Contain 'user3@contoso.com'
        }

        It 'handles multiple permission entries in a single step' {
            $step = [pscustomobject]@{
                Name = 'Multi-permission step'
                Type = 'IdLE.Step.Mailbox.EnsurePermissions'
                With = @{
                    Provider    = 'ExchangeOnline'
                    IdentityKey = 'shared@contoso.com'
                    Permissions = @(
                        @{ AssignedUser = 'user1@contoso.com'; Right = 'FullAccess';   Ensure = 'Present' }
                        @{ AssignedUser = 'user2@contoso.com'; Right = 'SendAs';       Ensure = 'Present' }
                        @{ AssignedUser = 'user3@contoso.com'; Right = 'SendOnBehalf'; Ensure = 'Present' }
                    )
                }
            }

            $handler = 'IdLE.Steps.Mailbox\Invoke-IdleStepMailboxPermissionsEnsure'
            $result = & $handler -Context $script:Context -Step $step

            $result.Status | Should -Be 'Completed'
            $result.Changed | Should -Be $true
            $script:Provider.Store.FullAccess['shared@contoso.com']['user1@contoso.com'] | Should -Be $true
            $script:Provider.Store.SendAs['shared@contoso.com']['user2@contoso.com'] | Should -Be $true
            $script:Provider.Store.SendOnBehalf['shared@contoso.com'] | Should -Contain 'user3@contoso.com'
        }
    }

    Context 'Validation' {
        It 'throws when Permissions is missing' {
            $step = [pscustomobject]@{
                Name = 'Missing Permissions'
                Type = 'IdLE.Step.Mailbox.EnsurePermissions'
                With = @{
                    Provider    = 'ExchangeOnline'
                    IdentityKey = 'shared@contoso.com'
                }
            }

            $handler = 'IdLE.Steps.Mailbox\Invoke-IdleStepMailboxPermissionsEnsure'
            { & $handler -Context $script:Context -Step $step } | Should -Throw "*requires With.Permissions*"
        }

        It 'throws when IdentityKey is missing' {
            $step = [pscustomobject]@{
                Name = 'Missing IdentityKey'
                Type = 'IdLE.Step.Mailbox.EnsurePermissions'
                With = @{
                    Provider    = 'ExchangeOnline'
                    Permissions = @(
                        @{ AssignedUser = 'user1@contoso.com'; Right = 'FullAccess'; Ensure = 'Present' }
                    )
                }
            }

            $handler = 'IdLE.Steps.Mailbox\Invoke-IdleStepMailboxPermissionsEnsure'
            { & $handler -Context $script:Context -Step $step } | Should -Throw "*requires With.IdentityKey*"
        }

        It 'throws when a Permissions entry is missing AssignedUser' {
            $step = [pscustomobject]@{
                Name = 'Bad entry'
                Type = 'IdLE.Step.Mailbox.EnsurePermissions'
                With = @{
                    Provider    = 'ExchangeOnline'
                    IdentityKey = 'shared@contoso.com'
                    Permissions = @(
                        @{ Right = 'FullAccess'; Ensure = 'Present' }
                    )
                }
            }

            $handler = 'IdLE.Steps.Mailbox\Invoke-IdleStepMailboxPermissionsEnsure'
            { & $handler -Context $script:Context -Step $step } | Should -Throw "*requires 'AssignedUser'*"
        }

        It 'throws when a Permissions entry has an invalid Right' {
            $step = [pscustomobject]@{
                Name = 'Invalid right'
                Type = 'IdLE.Step.Mailbox.EnsurePermissions'
                With = @{
                    Provider    = 'ExchangeOnline'
                    IdentityKey = 'shared@contoso.com'
                    Permissions = @(
                        @{ AssignedUser = 'user1@contoso.com'; Right = 'CalendarDelegate'; Ensure = 'Present' }
                    )
                }
            }

            $handler = 'IdLE.Steps.Mailbox\Invoke-IdleStepMailboxPermissionsEnsure'
            { & $handler -Context $script:Context -Step $step } | Should -Throw "*Right must be one of*"
        }

        It 'throws when a Permissions entry has an invalid Ensure value' {
            $step = [pscustomobject]@{
                Name = 'Invalid ensure'
                Type = 'IdLE.Step.Mailbox.EnsurePermissions'
                With = @{
                    Provider    = 'ExchangeOnline'
                    IdentityKey = 'shared@contoso.com'
                    Permissions = @(
                        @{ AssignedUser = 'user1@contoso.com'; Right = 'FullAccess'; Ensure = 'Maybe' }
                    )
                }
            }

            $handler = 'IdLE.Steps.Mailbox\Invoke-IdleStepMailboxPermissionsEnsure'
            { & $handler -Context $script:Context -Step $step } | Should -Throw "*Ensure must be one of*"
        }

        It 'rejects ScriptBlocks in Permissions (security boundary)' {
            $step = [pscustomobject]@{
                Name = 'ScriptBlock injection'
                Type = 'IdLE.Step.Mailbox.EnsurePermissions'
                With = @{
                    Provider    = 'ExchangeOnline'
                    IdentityKey = 'shared@contoso.com'
                    Permissions = @(
                        @{ AssignedUser = { 'injected' }; Right = 'FullAccess'; Ensure = 'Present' }
                    )
                }
            }

            $handler = 'IdLE.Steps.Mailbox\Invoke-IdleStepMailboxPermissionsEnsure'
            { & $handler -Context $script:Context -Step $step } | Should -Throw "*ScriptBlocks are not allowed*"
        }

        It 'throws when provider is missing' {
            $script:Context.Providers.Clear()

            $handler = 'IdLE.Steps.Mailbox\Invoke-IdleStepMailboxPermissionsEnsure'
            { & $handler -Context $script:Context -Step $script:StepTemplate } | Should -Throw -ErrorId *
        }
    }
}

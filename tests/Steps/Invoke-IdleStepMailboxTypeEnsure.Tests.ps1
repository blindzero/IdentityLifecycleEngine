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

Describe 'Invoke-IdleStepMailboxTypeEnsure' {
    BeforeEach {
        # Create mock ExchangeOnline provider
        $script:Provider = [pscustomobject]@{
            PSTypeName = 'Mock.ExchangeOnlineProvider'
            Store      = @{}
        }
        
        $script:Provider | Add-Member -MemberType ScriptMethod -Name EnsureMailboxType -Value {
            param($IdentityKey, $MailboxType, $AuthSession)
            
            if (-not $this.Store.ContainsKey($IdentityKey)) {
                throw "Mailbox '$IdentityKey' not found."
            }
            
            $mailbox = $this.Store[$IdentityKey]
            $currentType = $mailbox['Type']
            $changed = ($currentType -ne $MailboxType)
            
            if ($changed) {
                $mailbox['Type'] = $MailboxType
            }
            
            return [pscustomobject]@{
                PSTypeName  = 'IdLE.ProviderResult'
                Operation   = 'EnsureMailboxType'
                IdentityKey = $IdentityKey
                Changed     = $changed
                Type        = $MailboxType
            }
        } -Force
        
        # Add test mailbox
        $script:Provider.Store['user@contoso.com'] = @{
            IdentityKey = 'user@contoso.com'
            Type        = 'User'
        }
        
        $script:Context = [pscustomobject]@{
            PSTypeName = 'IdLE.ExecutionContext'
            Plan       = $null
            Providers  = @{ ExchangeOnline = $script:Provider }
            EventSink  = [pscustomobject]@{ WriteEvent = { param($Type, $Message, $StepName, $Data) } }
        }
        
        # Add mock AcquireAuthSession method
        $script:Context | Add-Member -MemberType ScriptMethod -Name AcquireAuthSession -Value {
            param($Name, $Options)
            return 'mock-token'
        } -Force
        
        $script:StepTemplate = [pscustomobject]@{
            Name = 'Convert to shared mailbox'
            Type = 'IdLE.Step.Mailbox.Type.Ensure'
            With = @{
                Provider    = 'ExchangeOnline'
                IdentityKey = 'user@contoso.com'
                MailboxType = 'Shared'
            }
        }
    }
    
    It 'converts mailbox type and reports Changed = true' {
        $handler = 'IdLE.Steps.Mailbox\Invoke-IdleStepMailboxTypeEnsure'
        $result = & $handler -Context $script:Context -Step $script:StepTemplate
        
        $result.Status | Should -Be 'Completed'
        $result.Changed | Should -Be $true
        
        # Verify mailbox was updated
        $script:Provider.Store['user@contoso.com']['Type'] | Should -Be 'Shared'
    }
    
    It 'is idempotent when mailbox already has desired type' {
        # Set mailbox to Shared first
        $script:Provider.Store['user@contoso.com']['Type'] = 'Shared'
        
        $handler = 'IdLE.Steps.Mailbox\Invoke-IdleStepMailboxTypeEnsure'
        $result = & $handler -Context $script:Context -Step $script:StepTemplate
        
        $result.Status | Should -Be 'Completed'
        $result.Changed | Should -Be $false
    }
    
    It 'throws when MailboxType is invalid' {
        $step = $script:StepTemplate
        $step.With.MailboxType = 'InvalidType'
        
        $handler = 'IdLE.Steps.Mailbox\Invoke-IdleStepMailboxTypeEnsure'
        { & $handler -Context $script:Context -Step $step } |
            Should -Throw "*MailboxType to be one of: User, Shared, Room, Equipment*"
    }
    
    It 'throws when provider is missing' {
        $script:Context.Providers.Clear()
        
        $handler = 'IdLE.Steps.Mailbox\Invoke-IdleStepMailboxTypeEnsure'
        { & $handler -Context $script:Context -Step $script:StepTemplate } | Should -Throw -ErrorId *
    }
    
    It 'throws when IdentityKey is missing' {
        $step = $script:StepTemplate
        $step.With.Remove('IdentityKey')
        
        $handler = 'IdLE.Steps.Mailbox\Invoke-IdleStepMailboxTypeEnsure'
        { & $handler -Context $script:Context -Step $step } | Should -Throw "*requires With.IdentityKey*"
    }
    
    It 'throws when MailboxType is missing' {
        $step = $script:StepTemplate
        $step.With.Remove('MailboxType')
        
        $handler = 'IdLE.Steps.Mailbox\Invoke-IdleStepMailboxTypeEnsure'
        { & $handler -Context $script:Context -Step $step } | Should -Throw "*requires With.MailboxType*"
    }
    
    It 'supports all valid mailbox types' {
        foreach ($type in @('Shared', 'Room', 'Equipment', 'User')) {
            # Always set to a different type first
            $startType = if ($type -eq 'User') { 'Shared' } else { 'User' }
            $script:Provider.Store['user@contoso.com']['Type'] = $startType
            
            $step = $script:StepTemplate
            $step.With.MailboxType = $type
            
            $handler = 'IdLE.Steps.Mailbox\Invoke-IdleStepMailboxTypeEnsure'
            $result = & $handler -Context $script:Context -Step $step
            
            $result.Changed | Should -Be $true
            $script:Provider.Store['user@contoso.com']['Type'] | Should -Be $type
        }
    }
}

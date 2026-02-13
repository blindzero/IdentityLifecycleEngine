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

Describe 'Invoke-IdleStepMailboxOutOfOfficeEnsure' {
    BeforeEach {
        # Create mock ExchangeOnline provider
        $script:Provider = [pscustomobject]@{
            PSTypeName = 'Mock.ExchangeOnlineProvider'
            Store      = @{}
        }
        
        $script:Provider | Add-Member -MemberType ScriptMethod -Name EnsureOutOfOffice -Value {
            param($IdentityKey, $Config, $AuthSession)
            
            if (-not $this.Store.ContainsKey($IdentityKey)) {
                throw "Mailbox '$IdentityKey' not found."
            }
            
            $mailbox = $this.Store[$IdentityKey]
            
            # Simple idempotency check based on Mode
            $changed = ($mailbox['OOFMode'] -ne $Config['Mode'])
            
            if ($changed) {
                $mailbox['OOFMode'] = $Config['Mode']
                $mailbox['OOFInternalMessage'] = if ($Config.ContainsKey('InternalMessage')) { $Config['InternalMessage'] } else { '' }
                $mailbox['OOFExternalMessage'] = if ($Config.ContainsKey('ExternalMessage')) { $Config['ExternalMessage'] } else { '' }
            }
            
            return [pscustomobject]@{
                PSTypeName  = 'IdLE.ProviderResult'
                Operation   = 'EnsureOutOfOffice'
                IdentityKey = $IdentityKey
                Changed     = $changed
            }
        } -Force
        
        # Add test mailbox
        $script:Provider.Store['user@contoso.com'] = @{
            IdentityKey         = 'user@contoso.com'
            OOFMode             = 'Disabled'
            OOFInternalMessage  = ''
            OOFExternalMessage  = ''
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
            Name = 'Enable Out of Office'
            Type = 'IdLE.Step.Mailbox.OutOfOffice.Ensure'
            With = @{
                Provider    = 'ExchangeOnline'
                IdentityKey = 'user@contoso.com'
                Config      = @{
                    Mode            = 'Enabled'
                    InternalMessage = 'I am out of office.'
                    ExternalMessage = 'Currently unavailable.'
                }
            }
        }
    }
    
    It 'enables Out of Office and reports Changed = true' {
        $handler = 'IdLE.Steps.Mailbox\Invoke-IdleStepMailboxOutOfOfficeEnsure'
        $result = & $handler -Context $script:Context -Step $script:StepTemplate
        
        $result.Status | Should -Be 'Completed'
        $result.Changed | Should -Be $true
        
        # Verify OOF was updated
        $script:Provider.Store['user@contoso.com']['OOFMode'] | Should -Be 'Enabled'
        $script:Provider.Store['user@contoso.com']['OOFInternalMessage'] | Should -Be 'I am out of office.'
    }
    
    It 'is idempotent when OOF already matches desired state' {
        # Set OOF to Enabled first
        $script:Provider.Store['user@contoso.com']['OOFMode'] = 'Enabled'
        
        $handler = 'IdLE.Steps.Mailbox\Invoke-IdleStepMailboxOutOfOfficeEnsure'
        $result = & $handler -Context $script:Context -Step $script:StepTemplate
        
        $result.Status | Should -Be 'Completed'
        $result.Changed | Should -Be $false
    }
    
    It 'disables Out of Office' {
        # First enable it
        $script:Provider.Store['user@contoso.com']['OOFMode'] = 'Enabled'
        
        $step = $script:StepTemplate
        $step.With.Config = @{ Mode = 'Disabled' }
        
        $handler = 'IdLE.Steps.Mailbox\Invoke-IdleStepMailboxOutOfOfficeEnsure'
        $result = & $handler -Context $script:Context -Step $step
        
        $result.Status | Should -Be 'Completed'
        $result.Changed | Should -Be $true
        $script:Provider.Store['user@contoso.com']['OOFMode'] | Should -Be 'Disabled'
    }
    
    It 'configures scheduled Out of Office' {
        $start = [DateTime]::Parse('2025-02-01T00:00:00Z')
        $end = [DateTime]::Parse('2025-02-15T00:00:00Z')
        
        $step = $script:StepTemplate
        $step.With.Config = @{
            Mode  = 'Scheduled'
            Start = $start
            End   = $end
            InternalMessage = 'On vacation'
        }
        
        $handler = 'IdLE.Steps.Mailbox\Invoke-IdleStepMailboxOutOfOfficeEnsure'
        $result = & $handler -Context $script:Context -Step $step
        
        $result.Status | Should -Be 'Completed'
        $result.Changed | Should -Be $true
        $script:Provider.Store['user@contoso.com']['OOFMode'] | Should -Be 'Scheduled'
    }
    
    It 'throws when Config is missing' {
        $step = $script:StepTemplate
        $step.With.Remove('Config')
        
        $handler = 'IdLE.Steps.Mailbox\Invoke-IdleStepMailboxOutOfOfficeEnsure'
        { & $handler -Context $script:Context -Step $step } | Should -Throw "*requires With.Config*"
    }
    
    It 'throws when Config.Mode is missing' {
        $step = $script:StepTemplate
        $step.With.Config = @{ InternalMessage = 'Test' }
        
        $handler = 'IdLE.Steps.Mailbox\Invoke-IdleStepMailboxOutOfOfficeEnsure'
        { & $handler -Context $script:Context -Step $step } | Should -Throw "*requires With.Config.Mode*"
    }
    
    It 'throws when Config.Mode is invalid' {
        $step = $script:StepTemplate
        $step.With.Config.Mode = 'InvalidMode'
        
        $handler = 'IdLE.Steps.Mailbox\Invoke-IdleStepMailboxOutOfOfficeEnsure'
        { & $handler -Context $script:Context -Step $step } |
            Should -Throw "*Mode to be one of: Disabled, Enabled, Scheduled*"
    }
    
    It 'throws when Scheduled mode is missing Start' {
        $step = $script:StepTemplate
        $step.With.Config = @{
            Mode = 'Scheduled'
            End  = [DateTime]::Now
        }
        
        $handler = 'IdLE.Steps.Mailbox\Invoke-IdleStepMailboxOutOfOfficeEnsure'
        { & $handler -Context $script:Context -Step $step } |
            Should -Throw "*Mode 'Scheduled' requires With.Config.Start*"
    }
    
    It 'throws when Scheduled mode is missing End' {
        $step = $script:StepTemplate
        $step.With.Config = @{
            Mode  = 'Scheduled'
            Start = [DateTime]::Now
        }
        
        $handler = 'IdLE.Steps.Mailbox\Invoke-IdleStepMailboxOutOfOfficeEnsure'
        { & $handler -Context $script:Context -Step $step } |
            Should -Throw "*Mode 'Scheduled' requires With.Config.End*"
    }
    
    It 'rejects ScriptBlocks in Config (security boundary)' {
        $step = $script:StepTemplate
        $step.With.Config.InternalMessage = { Write-Host "malicious" }
        
        $handler = 'IdLE.Steps.Mailbox\Invoke-IdleStepMailboxOutOfOfficeEnsure'
        { & $handler -Context $script:Context -Step $step } |
            Should -Throw "*ScriptBlocks are not allowed*"
    }
    
    It 'throws when provider is missing' {
        $script:Context.Providers.Clear()
        
        $handler = 'IdLE.Steps.Mailbox\Invoke-IdleStepMailboxOutOfOfficeEnsure'
        { & $handler -Context $script:Context -Step $script:StepTemplate } | Should -Throw -ErrorId *
    }
    
    It 'throws when IdentityKey is missing' {
        $step = $script:StepTemplate
        $step.With.Remove('IdentityKey')
        
        $handler = 'IdLE.Steps.Mailbox\Invoke-IdleStepMailboxOutOfOfficeEnsure'
        { & $handler -Context $script:Context -Step $step } | Should -Throw "*requires With.IdentityKey*"
    }
    
    It 'accepts MessageFormat = Text' {
        $step = $script:StepTemplate
        $step.With.Config.MessageFormat = 'Text'
        
        $handler = 'IdLE.Steps.Mailbox\Invoke-IdleStepMailboxOutOfOfficeEnsure'
        $result = & $handler -Context $script:Context -Step $step
        
        $result.Status | Should -Be 'Completed'
    }
    
    It 'accepts MessageFormat = Html' {
        $step = $script:StepTemplate
        $step.With.Config.MessageFormat = 'Html'
        
        $handler = 'IdLE.Steps.Mailbox\Invoke-IdleStepMailboxOutOfOfficeEnsure'
        $result = & $handler -Context $script:Context -Step $step
        
        $result.Status | Should -Be 'Completed'
    }
    
    It 'throws when MessageFormat is invalid' {
        $step = $script:StepTemplate
        $step.With.Config.MessageFormat = 'InvalidFormat'
        
        $handler = 'IdLE.Steps.Mailbox\Invoke-IdleStepMailboxOutOfOfficeEnsure'
        { & $handler -Context $script:Context -Step $step } |
            Should -Throw "*MessageFormat to be one of: Text, Html*"
    }
}

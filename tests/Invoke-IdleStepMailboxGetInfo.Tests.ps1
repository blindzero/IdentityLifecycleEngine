Set-StrictMode -Version Latest

BeforeAll {
    . (Join-Path $PSScriptRoot '_testHelpers.ps1')
    Import-IdleTestModule
    
    # Import Mailbox step pack
    $testsRoot = $PSScriptRoot
    $repoRoot = Split-Path -Path $testsRoot -Parent
    $mailboxModulePath = Join-Path -Path $repoRoot -ChildPath 'src\IdLE.Steps.Mailbox\IdLE.Steps.Mailbox.psm1'
    if (Test-Path -LiteralPath $mailboxModulePath -PathType Leaf) {
        Import-Module $mailboxModulePath -Force
    }
}

Describe 'Invoke-IdleStepMailboxGetInfo' {
    BeforeEach {
        # Create mock ExchangeOnline provider
        $script:Provider = [pscustomobject]@{
            PSTypeName = 'Mock.ExchangeOnlineProvider'
            Store      = @{}
        }
        
        $script:Provider | Add-Member -MemberType ScriptMethod -Name GetMailbox -Value {
            param($IdentityKey, $AuthSession)
            
            if (-not $this.Store.ContainsKey($IdentityKey)) {
                throw "Mailbox '$IdentityKey' not found."
            }
            
            return $this.Store[$IdentityKey]
        } -Force
        
        # Add test mailbox
        $script:Provider.Store['user@contoso.com'] = [pscustomobject]@{
            PSTypeName           = 'IdLE.Mailbox'
            IdentityKey          = 'user@contoso.com'
            PrimarySmtpAddress   = 'user@contoso.com'
            UserPrincipalName    = 'user@contoso.com'
            DisplayName          = 'Test User'
            Type                 = 'User'
            RecipientType        = 'UserMailbox'
            RecipientTypeDetails = 'UserMailbox'
            Guid                 = [System.Guid]::NewGuid().ToString()
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
            Name = 'Get mailbox info'
            Type = 'IdLE.Step.Mailbox.GetInfo'
            With = @{
                Provider    = 'ExchangeOnline'
                IdentityKey = 'user@contoso.com'
            }
        }
    }
    
    It 'retrieves mailbox and returns data in State' {
        $handler = 'IdLE.Steps.Mailbox\Invoke-IdleStepMailboxGetInfo'
        $result = & $handler -Context $script:Context -Step $script:StepTemplate
        
        $result.Status | Should -Be 'Completed'
        $result.Changed | Should -Be $false
        $result.State | Should -Not -BeNullOrEmpty
        $result.State.Mailbox | Should -Not -BeNullOrEmpty
        $result.State.Mailbox.IdentityKey | Should -Be 'user@contoso.com'
        $result.State.Mailbox.Type | Should -Be 'User'
    }
    
    It 'applies AuthSessionName convention (defaults to Provider)' {
        # Remove AuthSessionName to test default behavior
        $step = $script:StepTemplate
        $step.With.Remove('AuthSessionName')
        
        $handler = 'IdLE.Steps.Mailbox\Invoke-IdleStepMailboxGetInfo'
        $result = & $handler -Context $script:Context -Step $step
        
        $result.Status | Should -Be 'Completed'
        # AuthSessionName should have been set to 'ExchangeOnline'
        $step.With.AuthSessionName | Should -Be 'ExchangeOnline'
    }
    
    It 'throws when provider is missing' {
        $script:Context.Providers.Clear()
        
        $handler = 'IdLE.Steps.Mailbox\Invoke-IdleStepMailboxGetInfo'
        { & $handler -Context $script:Context -Step $script:StepTemplate } | Should -Throw -ErrorId *
    }
    
    It 'throws when IdentityKey is missing' {
        $step = $script:StepTemplate
        $step.With.Remove('IdentityKey')
        
        $handler = 'IdLE.Steps.Mailbox\Invoke-IdleStepMailboxGetInfo'
        { & $handler -Context $script:Context -Step $step } | Should -Throw "*requires With.IdentityKey*"
    }
}

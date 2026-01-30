BeforeAll {
    . (Join-Path (Split-Path -Path $PSScriptRoot -Parent) '_testHelpers.ps1')
    Import-IdleTestModule
}

Describe 'New-IdleAuthSession' {
    BeforeEach {
        # Create a test credential for use in tests
        $password = ConvertTo-SecureString 'TestPassword123!' -AsPlainText -Force
        $testCred = New-Object System.Management.Automation.PSCredential('TestUser', $password)
    }

    It 'creates an auth session broker with the expected type' {
        $broker = New-IdleAuthSession -SessionMap @{
            @{ Role = 'AD' } = $testCred
        }
        
        $broker | Should -Not -BeNullOrEmpty
        $broker.PSTypeNames | Should -Contain 'IdLE.AuthSessionBroker'
    }

    It 'creates broker with AcquireAuthSession method' {
        $broker = New-IdleAuthSession -SessionMap @{
            @{ Role = 'AD' } = $testCred
        }
        
        $broker.PSObject.Methods['AcquireAuthSession'] | Should -Not -BeNullOrEmpty
    }

    It 'accepts SessionMap parameter' {
        $sessionMap = @{
            @{ Role = 'Tier0' } = $testCred
            @{ Role = 'Admin' } = $testCred
        }
        
        $broker = New-IdleAuthSession -SessionMap $sessionMap
        
        $broker.SessionMap | Should -Not -BeNullOrEmpty
        $broker.SessionMap.Count | Should -Be 2
    }

    It 'accepts optional DefaultCredential parameter' {
        $broker = New-IdleAuthSession -SessionMap @{
            @{ Role = 'AD' } = $testCred
        } -DefaultCredential $testCred
        
        $broker.DefaultCredential | Should -Not -BeNullOrEmpty
        $broker.DefaultCredential.UserName | Should -Be 'TestUser'
    }

    It 'broker can acquire auth session with matching options' {
        $broker = New-IdleAuthSession -SessionMap @{
            @{ Role = 'Tier0' } = $testCred
        }
        
        $acquiredSession = $broker.AcquireAuthSession('TestName', @{ Role = 'Tier0' })
        
        $acquiredSession | Should -Not -BeNullOrEmpty
        $acquiredSession | Should -BeOfType [PSCredential]
        $acquiredSession.UserName | Should -Be 'TestUser'
    }

    It 'broker returns default credential when no options provided' {
        $defaultPassword = ConvertTo-SecureString 'DefaultPassword!' -AsPlainText -Force
        $defaultCred = New-Object System.Management.Automation.PSCredential('DefaultUser', $defaultPassword)
        
        $broker = New-IdleAuthSession -SessionMap @{
            @{ Role = 'Tier0' } = $testCred
        } -DefaultCredential $defaultCred
        
        $acquiredSession = $broker.AcquireAuthSession('TestName', $null)
        
        $acquiredSession | Should -Not -BeNullOrEmpty
        $acquiredSession.UserName | Should -Be 'DefaultUser'
    }

    It 'throws when no matching credential found and no default provided' {
        $broker = New-IdleAuthSession -SessionMap @{
            @{ Role = 'Tier0' } = $testCred
        }
        
        { $broker.AcquireAuthSession('TestName', @{ Role = 'NonExistent' }) } | 
            Should -Throw '*No matching credential found*'
    }

    It 'is available as exported command from IdLE module' {
        # This test ensures the command is properly exported and accessible
        $command = Get-Command -Name New-IdleAuthSession -ErrorAction SilentlyContinue
        
        $command | Should -Not -BeNullOrEmpty
        $command.Name | Should -Be 'New-IdleAuthSession'
        $command.Module.Name | Should -Be 'IdLE'
    }

    It 'delegates to IdLE.Core\New-IdleAuthSessionBroker correctly' {
        # This test ensures the underlying Core function is available and working
        # by verifying that New-IdleAuthSession can complete without errors
        { 
            $broker = New-IdleAuthSession -SessionMap @{
                @{ Role = 'AD' } = $testCred
            } -ErrorAction Stop
            
            $broker | Should -Not -BeNullOrEmpty
        } | Should -Not -Throw
    }
}

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
        } -AuthSessionType 'OAuth'
        
        $broker | Should -Not -BeNullOrEmpty
        $broker.PSTypeNames | Should -Contain 'IdLE.AuthSessionBroker'
    }

    It 'creates broker with AcquireAuthSession method' {
        $broker = New-IdleAuthSession -SessionMap @{
            @{ Role = 'AD' } = $testCred
        } -AuthSessionType 'OAuth'
        
        $broker.PSObject.Methods['AcquireAuthSession'] | Should -Not -BeNullOrEmpty
    }

    It 'accepts SessionMap parameter' {
        $sessionMap = @{
            @{ Role = 'Tier0' } = $testCred
            @{ Role = 'Admin' } = $testCred
        }
        
        $broker = New-IdleAuthSession -SessionMap $sessionMap -AuthSessionType 'Credential'
        
        $broker.SessionMap | Should -Not -BeNullOrEmpty
        $broker.SessionMap.Count | Should -Be 2
    }

    It 'accepts optional DefaultCredential parameter' {
        $broker = New-IdleAuthSession -SessionMap @{
            @{ Role = 'AD' } = $testCred
        } -DefaultCredential $testCred -AuthSessionType 'OAuth'
        
        $broker.DefaultCredential | Should -Not -BeNullOrEmpty
        $broker.DefaultCredential.UserName | Should -Be 'TestUser'
    }

    It 'broker can acquire auth session with matching options' {
        $broker = New-IdleAuthSession -SessionMap @{
            @{ Role = 'Tier0' } = $testCred
        } -AuthSessionType 'Credential'
        
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
        } -DefaultCredential $defaultCred -AuthSessionType 'OAuth'
        
        $acquiredSession = $broker.AcquireAuthSession('TestName', $null)
        
        $acquiredSession | Should -Not -BeNullOrEmpty
        $acquiredSession.UserName | Should -Be 'DefaultUser'
    }

    It 'throws when no matching credential found and no default provided' {
        $broker = New-IdleAuthSession -SessionMap @{
            @{ Role = 'Tier0' } = $testCred
        } -AuthSessionType 'OAuth'
        
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
            } -AuthSessionType 'Credential' -ErrorAction Stop
            
            $broker | Should -Not -BeNullOrEmpty
        } | Should -Not -Throw
    }

    Context 'AuthSessionType parameter' {
        It 'accepts OAuth session type' {
            $broker = New-IdleAuthSession -SessionMap @{
                @{ Role = 'Admin' } = $testCred
            } -AuthSessionType 'OAuth'
            
            $broker.AuthSessionType | Should -Be 'OAuth'
        }

        It 'accepts PSRemoting session type' {
            $broker = New-IdleAuthSession -SessionMap @{
                @{ Server = 'AADConnect01' } = $testCred
            } -AuthSessionType 'PSRemoting'
            
            $broker.AuthSessionType | Should -Be 'PSRemoting'
        }

        It 'accepts Credential session type' {
            $broker = New-IdleAuthSession -SessionMap @{
                @{ Domain = 'corp.example.com' } = $testCred
            } -AuthSessionType 'Credential'
            
            $broker.AuthSessionType | Should -Be 'Credential'
        }

        It 'throws on invalid session type' {
            { 
                New-IdleAuthSession -SessionMap @{
                    @{ Role = 'AD' } = $testCred
                } -AuthSessionType 'InvalidType'
            } | Should -Throw
        }
    }

    Context 'AuthSessionType validation during acquisition' {
        It 'OAuth broker can acquire sessions with appropriate options' {
            $broker = New-IdleAuthSession -SessionMap @{
                @{ Role = 'Admin' } = $testCred
            } -AuthSessionType 'OAuth'
            
            $session = $broker.AcquireAuthSession('MicrosoftGraph', @{ Role = 'Admin' })
            $session | Should -Not -BeNullOrEmpty
        }

        It 'PSRemoting broker can acquire sessions with appropriate options' {
            $broker = New-IdleAuthSession -SessionMap @{
                @{ Server = 'AADConnect01' } = $testCred
            } -AuthSessionType 'PSRemoting'
            
            $session = $broker.AcquireAuthSession('EntraConnect', @{ Server = 'AADConnect01' })
            $session | Should -Not -BeNullOrEmpty
        }

        It 'Credential broker can acquire sessions with appropriate options' {
            $broker = New-IdleAuthSession -SessionMap @{
                @{ Domain = 'corp.example.com' } = $testCred
            } -AuthSessionType 'Credential'
            
            $session = $broker.AcquireAuthSession('ActiveDirectory', @{ Domain = 'corp.example.com' })
            $session | Should -Not -BeNullOrEmpty
        }
    }
}

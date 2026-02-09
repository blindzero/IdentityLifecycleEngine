BeforeAll {
    . (Join-Path (Split-Path -Path $PSScriptRoot -Parent) '_testHelpers.ps1')
    Import-IdleTestModule
}

Describe 'New-IdleAuthSession' {
    BeforeEach {
        # Create test credentials and tokens for use in tests
        $password = ConvertTo-SecureString 'TestPassword123!' -AsPlainText -Force
        $testCred = New-Object System.Management.Automation.PSCredential('TestUser', $password)
        $testToken = 'mock-oauth-token-12345'
    }

    Context 'Simple syntax with AuthSessionType' {
        It 'creates broker with single credential' {
            $broker = New-IdleAuthSession -DefaultAuthSession $testCred -AuthSessionType 'Credential'
            
            $broker | Should -Not -BeNullOrEmpty
            $broker.PSTypeNames | Should -Contain 'IdLE.AuthSessionBroker'
        }

        It 'accepts SessionMap with untyped values when AuthSessionType provided' {
            $broker = New-IdleAuthSession -SessionMap @{
                @{ Role = 'Tier0' } = $testCred
                @{ Role = 'Admin' } = $testCred
            } -AuthSessionType 'Credential'
            
            $broker.SessionMap | Should -Not -BeNullOrEmpty
            $broker.SessionMap.Count | Should -Be 2
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

        It 'broker returns default auth session when no match found' {
            $defaultPassword = ConvertTo-SecureString 'DefaultPassword!' -AsPlainText -Force
            $defaultCred = New-Object System.Management.Automation.PSCredential('DefaultUser', $defaultPassword)
            
            $broker = New-IdleAuthSession -SessionMap @{
                @{ Role = 'Tier0' } = $testCred
            } -DefaultAuthSession $defaultCred -AuthSessionType 'Credential'
            
            $acquiredSession = $broker.AcquireAuthSession('TestName', $null)
            
            $acquiredSession | Should -Not -BeNullOrEmpty
            $acquiredSession.UserName | Should -Be 'DefaultUser'
        }

        It 'throws when no matching auth session found and no default provided' {
            $broker = New-IdleAuthSession -SessionMap @{
                @{ Role = 'Tier0' } = $testCred
            } -AuthSessionType 'Credential'
            
            { $broker.AcquireAuthSession('TestName', @{ Role = 'NonExistent' }) } | 
                Should -Throw '*No matching auth session found*'
        }

        It 'accepts OAuth session type' {
            $broker = New-IdleAuthSession -SessionMap @{
                @{ Role = 'Admin' } = $testToken
            } -AuthSessionType 'OAuth'
            
            $session = $broker.AcquireAuthSession('Graph', @{ Role = 'Admin' })
            $session | Should -BeOfType [string]
            $session | Should -Be 'mock-oauth-token-12345'
        }

        It 'accepts PSRemoting session type' {
            $broker = New-IdleAuthSession -SessionMap @{
                @{ Server = 'AADConnect01' } = $testCred
            } -AuthSessionType 'PSRemoting'
            
            $session = $broker.AcquireAuthSession('Remote', @{ Server = 'AADConnect01' })
            $session | Should -BeOfType [PSCredential]
        }
    }

    Context 'Typed syntax for mixed types' {
        It 'supports typed SessionMap values with AuthSessionType property' {
            $broker = New-IdleAuthSession -SessionMap @{
                @{ AuthSessionName = 'AD' } = @{ AuthSessionType = 'Credential'; Credential = $testCred }
            }

            $session = $broker.AcquireAuthSession('AD', $null)
            $session | Should -BeOfType [PSCredential]
        }

        It 'supports mixed types in single SessionMap' {
            $broker = New-IdleAuthSession -SessionMap @{
                @{ AuthSessionName = 'AD' } = @{ AuthSessionType = 'Credential'; Credential = $testCred }
                @{ AuthSessionName = 'EXO' } = @{ AuthSessionType = 'OAuth'; Credential = $testToken }
            }

            $adSession = $broker.AcquireAuthSession('AD', $null)
            $adSession | Should -BeOfType [PSCredential]

            $exoSession = $broker.AcquireAuthSession('EXO', $null)
            $exoSession | Should -BeOfType [string]
            $exoSession | Should -Be 'mock-oauth-token-12345'
        }

        It 'throws when untyped value provided without AuthSessionType' {
            {
                New-IdleAuthSession -SessionMap @{
                    @{ AuthSessionName = 'AD' } = $testCred  # Untyped
                }
            } | Should -Throw '*Untyped session value*'
        }

        It 'throws when invalid AuthSessionType provided' {
            {
                New-IdleAuthSession -SessionMap @{
                    @{ AuthSessionName = 'AD' } = @{ AuthSessionType = 'InvalidType'; Credential = $testCred }
                }
            } | Should -Throw '*Invalid AuthSessionType*'
        }
    }

    Context 'Type validation' {
        It 'validates Credential type matches PSCredential' {
            $broker = New-IdleAuthSession -DefaultAuthSession $testCred -AuthSessionType 'Credential'
            $session = $broker.AcquireAuthSession('', $null)
            $session | Should -BeOfType [PSCredential]
        }

        It 'throws when Credential type receives non-PSCredential object' {
            {
                $broker = New-IdleAuthSession -SessionMap @{
                    @{ AuthSessionName = 'AD' } = @{ AuthSessionType = 'Credential'; Credential = 'not-a-credential' }
                }
                $broker.AcquireAuthSession('AD', $null)
            } | Should -Throw '*Expected AuthSessionType=''Credential'' requires a*PSCredential*'
        }

        It 'validates OAuth type matches string token' {
            $broker = New-IdleAuthSession -DefaultAuthSession $testToken -AuthSessionType 'OAuth'
            $session = $broker.AcquireAuthSession('', $null)
            $session | Should -BeOfType [string]
        }

        It 'throws when OAuth type receives invalid object type' {
            {
                $broker = New-IdleAuthSession -SessionMap @{
                    @{ AuthSessionName = 'EXO' } = @{ AuthSessionType = 'OAuth'; Credential = [datetime]::Now }
                }
                $broker.AcquireAuthSession('EXO', $null)
            } | Should -Throw '*Expected AuthSessionType=''OAuth''*'
        }
    }

    Context 'AuthSessionName-based routing' {
        BeforeEach {
            $password1 = ConvertTo-SecureString 'Password1!' -AsPlainText -Force
            $cred1 = New-Object System.Management.Automation.PSCredential('ADAdm', $password1)
            
            $password2 = ConvertTo-SecureString 'Password2!' -AsPlainText -Force
            $cred2 = New-Object System.Management.Automation.PSCredential('EXOAdm', $password2)
            
            $password3 = ConvertTo-SecureString 'Password3!' -AsPlainText -Force
            $cred3 = New-Object System.Management.Automation.PSCredential('ADRead', $password3)
        }

        It 'matches AuthSessionName without options' {
            $broker = New-IdleAuthSession -SessionMap @{
                @{ AuthSessionName = 'AD' } = $cred1
                @{ AuthSessionName = 'EXO' } = $cred2
            } -AuthSessionType 'Credential'
            
            $session = $broker.AcquireAuthSession('AD', $null)
            $session.UserName | Should -Be 'ADAdm'
        }

        It 'matches AuthSessionName with matching options' {
            $broker = New-IdleAuthSession -SessionMap @{
                @{ AuthSessionName = 'AD'; Role = 'ADAdm' } = $cred1
                @{ AuthSessionName = 'AD'; Role = 'ADRead' } = $cred3
            } -AuthSessionType 'Credential'
            
            $session = $broker.AcquireAuthSession('AD', @{ Role = 'ADRead' })
            $session.UserName | Should -Be 'ADRead'
        }

        It 'falls back to default when AuthSessionName does not match' {
            $broker = New-IdleAuthSession -SessionMap @{
                @{ AuthSessionName = 'AD' } = $cred1
            } -DefaultAuthSession $testCred -AuthSessionType 'Credential'
            
            $session = $broker.AcquireAuthSession('EXO', $null)
            $session.UserName | Should -Be 'TestUser'
        }

        It 'throws when AuthSessionName matches multiple entries (ambiguous)' {
            $broker = New-IdleAuthSession -SessionMap @{
                @{ AuthSessionName = 'AD' } = $cred1
                @{ AuthSessionName = 'AD' } = $cred3
            } -AuthSessionType 'Credential'
            
            { $broker.AcquireAuthSession('AD', $null) } | Should -Throw '*Ambiguous*'
        }

        It 'prefers AuthSessionName match over Options-only match' {
            $broker = New-IdleAuthSession -SessionMap @{
                @{ Role = 'Admin' } = $testCred
                @{ AuthSessionName = 'AD'; Role = 'Admin' } = $cred1
            } -AuthSessionType 'Credential'
            
            $session = $broker.AcquireAuthSession('AD', @{ Role = 'Admin' })
            $session.UserName | Should -Be 'ADAdm'
        }

        It 'supports Options-only routing when AuthSessionName is not in pattern' {
            $broker = New-IdleAuthSession -SessionMap @{
                @{ Role = 'Tier0' } = $cred1
                @{ Role = 'Admin' } = $cred2
            } -AuthSessionType 'Credential'
            
            $session = $broker.AcquireAuthSession('AnyName', @{ Role = 'Admin' })
            $session.UserName | Should -Be 'EXOAdm'
        }
    }

    Context 'Optional SessionMap' {
        It 'creates broker with only DefaultAuthSession' {
            $broker = New-IdleAuthSession -DefaultAuthSession $testCred -AuthSessionType 'Credential'
            
            $broker | Should -Not -BeNullOrEmpty
            $broker.DefaultAuthSession | Should -Not -BeNullOrEmpty
        }

        It 'throws when SessionMap is null and DefaultAuthSession is not provided' {
            { 
                New-IdleAuthSession -SessionMap $null -AuthSessionType 'Credential'
            } | Should -Throw '*DefaultAuthSession must be provided*'
        }
    }

    It 'is available as exported command from IdLE module' {
        $command = Get-Command -Name New-IdleAuthSession -ErrorAction SilentlyContinue
        
        $command | Should -Not -BeNullOrEmpty
        $command.Name | Should -Be 'New-IdleAuthSession'
        $command.Module.Name | Should -Be 'IdLE'
    }
}

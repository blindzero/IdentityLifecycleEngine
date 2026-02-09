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

    It 'creates an auth session broker with the expected type' {
        $broker = New-IdleAuthSession -SessionMap @{
            @{ Role = 'AD' } = @{ AuthSessionType = 'Credential'; Session = $testCred }
        }
        
        $broker | Should -Not -BeNullOrEmpty
        $broker.PSTypeNames | Should -Contain 'IdLE.AuthSessionBroker'
    }

    It 'creates broker with AcquireAuthSession method' {
        $broker = New-IdleAuthSession -SessionMap @{
            @{ Role = 'AD' } = @{ AuthSessionType = 'Credential'; Session = $testCred }
        }
        
        $broker.PSObject.Methods['AcquireAuthSession'] | Should -Not -BeNullOrEmpty
    }

    It 'accepts SessionMap parameter with typed values' {
        $sessionMap = @{
            @{ Role = 'Tier0' } = @{ AuthSessionType = 'Credential'; Session = $testCred }
            @{ Role = 'Admin' } = @{ AuthSessionType = 'Credential'; Session = $testCred }
        }
        
        $broker = New-IdleAuthSession -SessionMap $sessionMap
        
        $broker.SessionMap | Should -Not -BeNullOrEmpty
        $broker.SessionMap.Count | Should -Be 2
    }

    It 'accepts optional DefaultAuthSession parameter' {
        $broker = New-IdleAuthSession -SessionMap @{
            @{ Role = 'AD' } = @{ AuthSessionType = 'Credential'; Session = $testCred }
        } -DefaultAuthSession @{ AuthSessionType = 'Credential'; Session = $testCred }
        
        $broker.DefaultAuthSession | Should -Not -BeNullOrEmpty
        # Test via AcquireAuthSession (empty name signals default)
        $session = $broker.AcquireAuthSession('', $null)
        $session.UserName | Should -Be 'TestUser'
    }

    It 'broker can acquire auth session with matching options' {
        $broker = New-IdleAuthSession -SessionMap @{
            @{ Role = 'Tier0' } = @{ AuthSessionType = 'Credential'; Session = $testCred }
        }
        
        $acquiredSession = $broker.AcquireAuthSession('TestName', @{ Role = 'Tier0' })
        
        $acquiredSession | Should -Not -BeNullOrEmpty
        $acquiredSession | Should -BeOfType [PSCredential]
        $acquiredSession.UserName | Should -Be 'TestUser'
    }

    It 'broker returns default auth session when no match found' {
        $defaultPassword = ConvertTo-SecureString 'DefaultPassword!' -AsPlainText -Force
        $defaultCred = New-Object System.Management.Automation.PSCredential('DefaultUser', $defaultPassword)
        
        $broker = New-IdleAuthSession -SessionMap @{
            @{ Role = 'Tier0' } = @{ AuthSessionType = 'Credential'; Session = $testCred }
        } -DefaultAuthSession @{ AuthSessionType = 'Credential'; Session = $defaultCred }
        
        $acquiredSession = $broker.AcquireAuthSession('TestName', $null)
        
        $acquiredSession | Should -Not -BeNullOrEmpty
        $acquiredSession.UserName | Should -Be 'DefaultUser'
    }

    It 'throws when no matching auth session found and no default provided' {
        $broker = New-IdleAuthSession -SessionMap @{
            @{ Role = 'Tier0' } = @{ AuthSessionType = 'Credential'; Session = $testCred }
        }
        
        { $broker.AcquireAuthSession('TestName', @{ Role = 'NonExistent' }) } | 
            Should -Throw '*No matching auth session found*'
    }

    It 'is available as exported command from IdLE module' {
        $command = Get-Command -Name New-IdleAuthSession -ErrorAction SilentlyContinue
        
        $command | Should -Not -BeNullOrEmpty
        $command.Name | Should -Be 'New-IdleAuthSession'
        $command.Module.Name | Should -Be 'IdLE'
    }

    It 'delegates to IdLE.Core\New-IdleAuthSessionBroker correctly' {
        { 
            $broker = New-IdleAuthSession -SessionMap @{
                @{ Role = 'AD' } = @{ AuthSessionType = 'Credential'; Session = $testCred }
            } -ErrorAction Stop
            
            $broker | Should -Not -BeNullOrEmpty
        } | Should -Not -Throw
    }

    Context 'Typed session validation' {
        It 'accepts Credential session type' {
            $broker = New-IdleAuthSession -SessionMap @{
                @{ Domain = 'corp.example.com' } = @{ AuthSessionType = 'Credential'; Session = $testCred }
            }
            
            $session = $broker.AcquireAuthSession('AD', @{ Domain = 'corp.example.com' })
            $session | Should -BeOfType [PSCredential]
        }

        It 'accepts OAuth session type' {
            $broker = New-IdleAuthSession -SessionMap @{
                @{ Role = 'Admin' } = @{ AuthSessionType = 'OAuth'; Session = $testToken }
            }
            
            $session = $broker.AcquireAuthSession('Graph', @{ Role = 'Admin' })
            $session | Should -BeOfType [string]
            $session | Should -Be 'mock-oauth-token-12345'
        }

        It 'accepts PSRemoting session type' {
            $broker = New-IdleAuthSession -SessionMap @{
                @{ Server = 'AADConnect01' } = @{ AuthSessionType = 'PSRemoting'; Session = $testCred }
            }
            
            $session = $broker.AcquireAuthSession('Remote', @{ Server = 'AADConnect01' })
            $session | Should -BeOfType [PSCredential]
        }

        It 'validates Credential type matches PSCredential' {
            $broker = New-IdleAuthSession -SessionMap @{
                @{ AuthSessionName = 'AD' } = @{ AuthSessionType = 'Credential'; Session = $testCred }
            }

            # Should succeed
            $session = $broker.AcquireAuthSession('AD', $null)
            $session | Should -BeOfType [PSCredential]
        }

        It 'throws when Credential type receives non-PSCredential object' {
            {
                $broker = New-IdleAuthSession -SessionMap @{
                    @{ AuthSessionName = 'AD' } = @{ AuthSessionType = 'Credential'; Session = 'not-a-credential' }
                }
                $broker.AcquireAuthSession('AD', $null)
            } | Should -Throw '*Expected AuthSessionType=''Credential'' requires a*PSCredential*'
        }

        It 'validates OAuth type matches string token' {
            $broker = New-IdleAuthSession -SessionMap @{
                @{ AuthSessionName = 'EXO' } = @{ AuthSessionType = 'OAuth'; Session = $testToken }
            }

            # Should succeed
            $session = $broker.AcquireAuthSession('EXO', $null)
            $session | Should -BeOfType [string]
        }

        It 'throws when OAuth type receives non-string object' {
            {
                $broker = New-IdleAuthSession -SessionMap @{
                    @{ AuthSessionName = 'EXO' } = @{ AuthSessionType = 'OAuth'; Session = $testCred }
                }
                $broker.AcquireAuthSession('EXO', $null)
            } | Should -Throw '*Expected AuthSessionType=''OAuth'' requires a*string*'
        }

        It 'validates PSRemoting type matches PSCredential' {
            $broker = New-IdleAuthSession -SessionMap @{
                @{ AuthSessionName = 'Remote' } = @{ AuthSessionType = 'PSRemoting'; Session = $testCred }
            }

            # Should succeed (PSCredential is valid for PSRemoting)
            $session = $broker.AcquireAuthSession('Remote', $null)
            $session | Should -BeOfType [PSCredential]
        }

        It 'throws when PSRemoting type receives invalid object' {
            {
                $broker = New-IdleAuthSession -SessionMap @{
                    @{ AuthSessionName = 'Remote' } = @{ AuthSessionType = 'PSRemoting'; Session = 'not-valid' }
                }
                $broker.AcquireAuthSession('Remote', $null)
            } | Should -Throw '*Expected AuthSessionType=''PSRemoting''*'
        }

        It 'throws when invalid AuthSessionType provided' {
            {
                New-IdleAuthSession -SessionMap @{
                    @{ AuthSessionName = 'AD' } = @{ AuthSessionType = 'InvalidType'; Session = $testCred }
                }
            } | Should -Throw '*Invalid AuthSessionType*'
        }

        It 'throws when untyped session value provided' {
            {
                New-IdleAuthSession -SessionMap @{
                    @{ AuthSessionName = 'AD' } = $testCred  # Untyped
                }
            } | Should -Throw '*must be a typed session descriptor*'
        }

        It 'throws when untyped DefaultAuthSession provided' {
            {
                New-IdleAuthSession -SessionMap @{
                    @{ AuthSessionName = 'AD' } = @{ AuthSessionType = 'Credential'; Session = $testCred }
                } -DefaultAuthSession $testCred  # Untyped default
            } | Should -Throw '*must be a typed session descriptor*'
        }

        It 'throws with clear error including session name on type mismatch' {
            {
                $broker = New-IdleAuthSession -SessionMap @{
                    @{ AuthSessionName = 'MyCustomSession' } = @{ AuthSessionType = 'Credential'; Session = 'wrong-type' }
                }
                $broker.AcquireAuthSession('MyCustomSession', $null)
            } | Should -Throw '*MyCustomSession*'
        }
    }

    Context 'Optional SessionMap' {
        It 'creates broker with only DefaultAuthSession (no SessionMap)' {
            $broker = New-IdleAuthSession -DefaultAuthSession @{ AuthSessionType = 'Credential'; Session = $testCred }
            
            $broker | Should -Not -BeNullOrEmpty
            $broker.DefaultAuthSession | Should -Not -BeNullOrEmpty
            $broker.SessionMap | Should -BeNullOrEmpty
        }

        It 'returns DefaultAuthSession when SessionMap is null' {
            $broker = New-IdleAuthSession -DefaultAuthSession @{ AuthSessionType = 'Credential'; Session = $testCred }
            
            $session = $broker.AcquireAuthSession('AnyName', $null)
            
            $session | Should -Not -BeNullOrEmpty
            $session.UserName | Should -Be 'TestUser'
        }

        It 'returns DefaultAuthSession when SessionMap is empty' {
            $broker = New-IdleAuthSession -SessionMap @{} -DefaultAuthSession @{ AuthSessionType = 'Credential'; Session = $testCred }
            
            $session = $broker.AcquireAuthSession('AnyName', $null)
            
            $session | Should -Not -BeNullOrEmpty
            $session.UserName | Should -Be 'TestUser'
        }

        It 'throws when SessionMap is null and DefaultAuthSession is not provided' {
            { 
                New-IdleAuthSession -SessionMap $null
            } | Should -Throw '*DefaultAuthSession must be provided*'
        }

        It 'throws when SessionMap is empty and DefaultAuthSession is not provided' {
            { 
                New-IdleAuthSession -SessionMap @{}
            } | Should -Throw '*DefaultAuthSession must be provided*'
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
                @{ AuthSessionName = 'AD' } = @{ AuthSessionType = 'Credential'; Session = $cred1 }
                @{ AuthSessionName = 'EXO' } = @{ AuthSessionType = 'Credential'; Session = $cred2 }
            }
            
            $session = $broker.AcquireAuthSession('AD', $null)
            
            $session | Should -Not -BeNullOrEmpty
            $session.UserName | Should -Be 'ADAdm'
        }

        It 'matches AuthSessionName with matching options' {
            $broker = New-IdleAuthSession -SessionMap @{
                @{ AuthSessionName = 'AD'; Role = 'ADAdm' } = @{ AuthSessionType = 'Credential'; Session = $cred1 }
                @{ AuthSessionName = 'AD'; Role = 'ADRead' } = @{ AuthSessionType = 'Credential'; Session = $cred3 }
            }
            
            $session = $broker.AcquireAuthSession('AD', @{ Role = 'ADRead' })
            
            $session | Should -Not -BeNullOrEmpty
            $session.UserName | Should -Be 'ADRead'
        }

        It 'falls back to default when AuthSessionName does not match' {
            $broker = New-IdleAuthSession -SessionMap @{
                @{ AuthSessionName = 'AD' } = @{ AuthSessionType = 'Credential'; Session = $cred1 }
            } -DefaultAuthSession @{ AuthSessionType = 'Credential'; Session = $testCred }
            
            $session = $broker.AcquireAuthSession('EXO', $null)
            
            $session | Should -Not -BeNullOrEmpty
            $session.UserName | Should -Be 'TestUser'
        }

        It 'throws when AuthSessionName matches multiple entries (ambiguous)' {
            $broker = New-IdleAuthSession -SessionMap @{
                @{ AuthSessionName = 'AD' } = @{ AuthSessionType = 'Credential'; Session = $cred1 }
                @{ AuthSessionName = 'AD' } = @{ AuthSessionType = 'Credential'; Session = $cred3 }
            }
            
            { $broker.AcquireAuthSession('AD', $null) } | 
                Should -Throw '*Ambiguous*'
        }

        It 'prefers AuthSessionName match over Options-only match' {
            $broker = New-IdleAuthSession -SessionMap @{
                @{ Role = 'Admin' } = @{ AuthSessionType = 'Credential'; Session = $testCred }
                @{ AuthSessionName = 'AD'; Role = 'Admin' } = @{ AuthSessionType = 'Credential'; Session = $cred1 }
            }
            
            $session = $broker.AcquireAuthSession('AD', @{ Role = 'Admin' })
            
            $session | Should -Not -BeNullOrEmpty
            $session.UserName | Should -Be 'ADAdm'
        }

        It 'supports Options-only routing when AuthSessionName is not in pattern' {
            $broker = New-IdleAuthSession -SessionMap @{
                @{ Role = 'Tier0' } = @{ AuthSessionType = 'Credential'; Session = $cred1 }
                @{ Role = 'Admin' } = @{ AuthSessionType = 'Credential'; Session = $cred2 }
            }
            
            $session = $broker.AcquireAuthSession('AnyName', @{ Role = 'Admin' })
            
            $session | Should -Not -BeNullOrEmpty
            $session.UserName | Should -Be 'EXOAdm'
        }

        It 'throws when AuthSessionName does not match and no default provided' {
            $broker = New-IdleAuthSession -SessionMap @{
                @{ AuthSessionName = 'AD' } = @{ AuthSessionType = 'Credential'; Session = $cred1 }
            }
            
            { $broker.AcquireAuthSession('EXO', $null) } | 
                Should -Throw '*No matching auth session found*'
        }

        It 'matches complex pattern: AuthSessionName + multiple options' {
            $broker = New-IdleAuthSession -SessionMap @{
                @{ AuthSessionName = 'AD'; Role = 'Admin'; Environment = 'Prod' } = @{ AuthSessionType = 'Credential'; Session = $cred1 }
            }
            
            $session = $broker.AcquireAuthSession('AD', @{ Role = 'Admin'; Environment = 'Prod' })
            
            $session | Should -Not -BeNullOrEmpty
            $session.UserName | Should -Be 'ADAdm'
        }

        It 'does not match when partial options provided' {
            $broker = New-IdleAuthSession -SessionMap @{
                @{ AuthSessionName = 'AD'; Role = 'Admin'; Environment = 'Prod' } = @{ AuthSessionType = 'Credential'; Session = $cred1 }
            } -DefaultAuthSession @{ AuthSessionType = 'Credential'; Session = $testCred }
            
            # Only providing Role, not Environment - should fall back to default
            $session = $broker.AcquireAuthSession('AD', @{ Role = 'Admin' })
            
            $session | Should -Not -BeNullOrEmpty
            $session.UserName | Should -Be 'TestUser'
        }
    }

    Context 'Mixed authentication types' {
        BeforeEach {
            $password = ConvertTo-SecureString 'Password!' -AsPlainText -Force
            $adCred = New-Object System.Management.Automation.PSCredential('ADUser', $password)
            $exoToken = 'mock-oauth-token-12345'
        }

        It 'supports mixed types in single SessionMap' {
            $broker = New-IdleAuthSession -SessionMap @{
                @{ AuthSessionName = 'AD' } = @{ AuthSessionType = 'Credential'; Session = $adCred }
                @{ AuthSessionName = 'EXO' } = @{ AuthSessionType = 'OAuth'; Session = $exoToken }
            }

            $adSession = $broker.AcquireAuthSession('AD', $null)
            $adSession | Should -BeOfType [PSCredential]

            $exoSession = $broker.AcquireAuthSession('EXO', $null)
            $exoSession | Should -BeOfType [string]
            $exoSession | Should -Be 'mock-oauth-token-12345'
        }

        It 'validates typed DefaultAuthSession with different type than SessionMap' {
            $broker = New-IdleAuthSession -SessionMap @{
                @{ AuthSessionName = 'AD' } = @{ AuthSessionType = 'Credential'; Session = $adCred }
            } -DefaultAuthSession @{ AuthSessionType = 'OAuth'; Session = $exoToken }

            $defaultSession = $broker.AcquireAuthSession('Unknown', $null)
            $defaultSession | Should -BeOfType [string]
            $defaultSession | Should -Be 'mock-oauth-token-12345'
        }

        It 'multi-provider scenario: AD (Credential) + EXO (OAuth)' {
            # Real-world scenario: mixed authentication types in single broker
            $broker = New-IdleAuthSession -SessionMap @{
                @{ AuthSessionName = 'AD'; Role = 'Admin' } = @{ AuthSessionType = 'Credential'; Session = $adCred }
                @{ AuthSessionName = 'EXO' } = @{ AuthSessionType = 'OAuth'; Session = $exoToken }
            }

            # Acquire AD session
            $adSession = $broker.AcquireAuthSession('AD', @{ Role = 'Admin' })
            $adSession | Should -BeOfType [PSCredential]
            $adSession.UserName | Should -Be 'ADUser'

            # Acquire EXO session
            $exoSession = $broker.AcquireAuthSession('EXO', $null)
            $exoSession | Should -BeOfType [string]
            $exoSession | Should -Be 'mock-oauth-token-12345'
        }

        It 'supports PSCustomObject format for typed sessions' {
            $typedSession = [pscustomobject]@{
                AuthSessionType = 'OAuth'
                Session = $exoToken
            }

            $broker = New-IdleAuthSession -SessionMap @{
                @{ AuthSessionName = 'EXO' } = $typedSession
            }

            $session = $broker.AcquireAuthSession('EXO', $null)
            $session | Should -BeOfType [string]
            $session | Should -Be 'mock-oauth-token-12345'
        }
    }
}

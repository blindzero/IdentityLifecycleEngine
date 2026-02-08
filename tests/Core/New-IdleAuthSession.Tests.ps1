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
        } -AuthSessionType 'Credential'
        
        $broker | Should -Not -BeNullOrEmpty
        $broker.PSTypeNames | Should -Contain 'IdLE.AuthSessionBroker'
    }

    It 'creates broker with AcquireAuthSession method' {
        $broker = New-IdleAuthSession -SessionMap @{
            @{ Role = 'AD' } = $testCred
        } -AuthSessionType 'Credential'
        
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

    It 'accepts optional DefaultAuthSession parameter' {
        $broker = New-IdleAuthSession -SessionMap @{
            @{ Role = 'AD' } = $testCred
        } -DefaultAuthSession $testCred -AuthSessionType 'Credential'
        
        $broker.DefaultAuthSession | Should -Not -BeNullOrEmpty
        # Note: DefaultAuthSession is now normalized internally, test via AcquireAuthSession
        $session = $broker.AcquireAuthSession('', $null)
        $session.UserName | Should -Be 'TestUser'
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

    It 'broker returns default auth session when no options provided' {
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
            $oauthToken = 'mock-oauth-token'
            $broker = New-IdleAuthSession -SessionMap @{
                @{ Role = 'Admin' } = $oauthToken
            } -AuthSessionType 'OAuth'
            
            $session = $broker.AcquireAuthSession('MicrosoftGraph', @{ Role = 'Admin' })
            $session | Should -Not -BeNullOrEmpty
            $session | Should -BeOfType [string]
        }

        It 'PSRemoting broker can acquire sessions with appropriate options' {
            $broker = New-IdleAuthSession -SessionMap @{
                @{ Server = 'AADConnect01' } = $testCred
            } -AuthSessionType 'PSRemoting'
            
            $session = $broker.AcquireAuthSession('EntraConnect', @{ Server = 'AADConnect01' })
            $session | Should -Not -BeNullOrEmpty
            $session | Should -BeOfType [PSCredential]
        }

        It 'Credential broker can acquire sessions with appropriate options' {
            $broker = New-IdleAuthSession -SessionMap @{
                @{ Domain = 'corp.example.com' } = $testCred
            } -AuthSessionType 'Credential'
            
            $session = $broker.AcquireAuthSession('ActiveDirectory', @{ Domain = 'corp.example.com' })
            $session | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Optional SessionMap' {
        It 'creates broker with only DefaultAuthSession (no SessionMap)' {
            $broker = New-IdleAuthSession -DefaultAuthSession $testCred -AuthSessionType 'Credential'
            
            $broker | Should -Not -BeNullOrEmpty
            $broker.DefaultAuthSession | Should -Not -BeNullOrEmpty
            $broker.SessionMap | Should -BeNullOrEmpty
        }

        It 'returns DefaultAuthSession when SessionMap is null' {
            $broker = New-IdleAuthSession -DefaultAuthSession $testCred -AuthSessionType 'Credential'
            
            $session = $broker.AcquireAuthSession('AnyName', $null)
            
            $session | Should -Not -BeNullOrEmpty
            $session.UserName | Should -Be 'TestUser'
        }

        It 'returns DefaultAuthSession when SessionMap is empty' {
            $broker = New-IdleAuthSession -SessionMap @{} -DefaultAuthSession $testCred -AuthSessionType 'Credential'
            
            $session = $broker.AcquireAuthSession('AnyName', $null)
            
            $session | Should -Not -BeNullOrEmpty
            $session.UserName | Should -Be 'TestUser'
        }

        It 'throws when SessionMap is null and DefaultAuthSession is not provided' {
            { 
                New-IdleAuthSession -SessionMap $null -AuthSessionType 'Credential'
            } | Should -Throw '*DefaultAuthSession must be provided*'
        }

        It 'throws when SessionMap is empty and DefaultAuthSession is not provided' {
            { 
                New-IdleAuthSession -SessionMap @{} -AuthSessionType 'Credential'
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
                @{ AuthSessionName = 'AD' } = $cred1
                @{ AuthSessionName = 'EXO' } = $cred2
            } -AuthSessionType 'Credential'
            
            $session = $broker.AcquireAuthSession('AD', $null)
            
            $session | Should -Not -BeNullOrEmpty
            $session.UserName | Should -Be 'ADAdm'
        }

        It 'matches AuthSessionName with matching options' {
            $broker = New-IdleAuthSession -SessionMap @{
                @{ AuthSessionName = 'AD'; Role = 'ADAdm' } = $cred1
                @{ AuthSessionName = 'AD'; Role = 'ADRead' } = $cred3
            } -AuthSessionType 'Credential'
            
            $session = $broker.AcquireAuthSession('AD', @{ Role = 'ADRead' })
            
            $session | Should -Not -BeNullOrEmpty
            $session.UserName | Should -Be 'ADRead'
        }

        It 'falls back to default when AuthSessionName does not match' {
            $broker = New-IdleAuthSession -SessionMap @{
                @{ AuthSessionName = 'AD' } = $cred1
            } -DefaultAuthSession $testCred -AuthSessionType 'Credential'
            
            $session = $broker.AcquireAuthSession('EXO', $null)
            
            $session | Should -Not -BeNullOrEmpty
            $session.UserName | Should -Be 'TestUser'
        }

        It 'throws when AuthSessionName matches multiple entries (ambiguous)' {
            $broker = New-IdleAuthSession -SessionMap @{
                @{ AuthSessionName = 'AD' } = $cred1
                @{ AuthSessionName = 'AD' } = $cred3
            } -AuthSessionType 'Credential'
            
            { $broker.AcquireAuthSession('AD', $null) } | 
                Should -Throw '*Ambiguous*'
        }

        It 'prefers AuthSessionName match over legacy Options-only match' {
            $broker = New-IdleAuthSession -SessionMap @{
                @{ Role = 'Admin' } = $testCred
                @{ AuthSessionName = 'AD'; Role = 'Admin' } = $cred1
            } -AuthSessionType 'Credential'
            
            $session = $broker.AcquireAuthSession('AD', @{ Role = 'Admin' })
            
            $session | Should -Not -BeNullOrEmpty
            $session.UserName | Should -Be 'ADAdm'
        }

        It 'supports legacy Options-only routing when AuthSessionName is not in pattern' {
            $broker = New-IdleAuthSession -SessionMap @{
                @{ Role = 'Tier0' } = $cred1
                @{ Role = 'Admin' } = $cred2
            } -AuthSessionType 'Credential'
            
            $session = $broker.AcquireAuthSession('AnyName', @{ Role = 'Admin' })
            
            $session | Should -Not -BeNullOrEmpty
            $session.UserName | Should -Be 'EXOAdm'
        }

        It 'throws when AuthSessionName does not match and no default provided' {
            $broker = New-IdleAuthSession -SessionMap @{
                @{ AuthSessionName = 'AD' } = $cred1
            } -AuthSessionType 'Credential'
            
            { $broker.AcquireAuthSession('EXO', $null) } | 
                Should -Throw '*No matching auth session found*'
        }

        It 'matches complex pattern: AuthSessionName + multiple options' {
            $broker = New-IdleAuthSession -SessionMap @{
                @{ AuthSessionName = 'AD'; Role = 'Admin'; Environment = 'Prod' } = $cred1
            } -AuthSessionType 'Credential'
            
            $session = $broker.AcquireAuthSession('AD', @{ Role = 'Admin'; Environment = 'Prod' })
            
            $session | Should -Not -BeNullOrEmpty
            $session.UserName | Should -Be 'ADAdm'
        }

        It 'does not match when partial options provided' {
            $broker = New-IdleAuthSession -SessionMap @{
                @{ AuthSessionName = 'AD'; Role = 'Admin'; Environment = 'Prod' } = $cred1
            } -DefaultAuthSession $testCred -AuthSessionType 'Credential'
            
            # Only providing Role, not Environment - should fall back to default
            $session = $broker.AcquireAuthSession('AD', @{ Role = 'Admin' })
            
            $session | Should -Not -BeNullOrEmpty
            $session.UserName | Should -Be 'TestUser'
        }
    }

    Context 'Per-entry AuthSessionType support' {
        BeforeEach {
            $password = ConvertTo-SecureString 'Password!' -AsPlainText -Force
            $adCred = New-Object System.Management.Automation.PSCredential('ADUser', $password)
            $exoToken = 'mock-oauth-token-12345'
        }

        It 'supports typed SessionMap values with AuthSessionType property' {
            $broker = New-IdleAuthSession -SessionMap @{
                @{ AuthSessionName = 'AD' } = @{ AuthSessionType = 'Credential'; Session = $adCred }
            }

            $session = $broker.AcquireAuthSession('AD', $null)

            $session | Should -Not -BeNullOrEmpty
            $session | Should -BeOfType [PSCredential]
            $session.UserName | Should -Be 'ADUser'
        }

        It 'supports mixed typed and untyped SessionMap values with default AuthSessionType' {
            $broker = New-IdleAuthSession -SessionMap @{
                @{ AuthSessionName = 'AD' } = $adCred  # Untyped, uses default
                @{ AuthSessionName = 'EXO' } = @{ AuthSessionType = 'OAuth'; Session = $exoToken }  # Typed
            } -AuthSessionType 'Credential'

            $adSession = $broker.AcquireAuthSession('AD', $null)
            $adSession | Should -BeOfType [PSCredential]

            $exoSession = $broker.AcquireAuthSession('EXO', $null)
            $exoSession | Should -BeOfType [string]
            $exoSession | Should -Be 'mock-oauth-token-12345'
        }

        It 'supports all typed SessionMap values without -AuthSessionType' {
            $broker = New-IdleAuthSession -SessionMap @{
                @{ AuthSessionName = 'AD' } = @{ AuthSessionType = 'Credential'; Session = $adCred }
                @{ AuthSessionName = 'EXO' } = @{ AuthSessionType = 'OAuth'; Session = $exoToken }
            }

            $adSession = $broker.AcquireAuthSession('AD', $null)
            $adSession | Should -BeOfType [PSCredential]

            $exoSession = $broker.AcquireAuthSession('EXO', $null)
            $exoSession | Should -BeOfType [string]
        }

        It 'throws when untyped SessionMap value provided without -AuthSessionType' {
            {
                New-IdleAuthSession -SessionMap @{
                    @{ AuthSessionName = 'AD' } = $adCred  # Untyped
                }
            } | Should -Throw '*Untyped session value*'
        }

        It 'throws when untyped DefaultAuthSession provided without -AuthSessionType' {
            {
                New-IdleAuthSession -SessionMap @{
                    @{ AuthSessionName = 'AD' } = @{ AuthSessionType = 'Credential'; Session = $adCred }
                } -DefaultAuthSession $adCred  # Untyped default
            } | Should -Throw '*Untyped session value*'
        }

        It 'validates Credential type matches PSCredential' {
            $broker = New-IdleAuthSession -SessionMap @{
                @{ AuthSessionName = 'AD' } = @{ AuthSessionType = 'Credential'; Session = $adCred }
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
                @{ AuthSessionName = 'EXO' } = @{ AuthSessionType = 'OAuth'; Session = $exoToken }
            }

            # Should succeed
            $session = $broker.AcquireAuthSession('EXO', $null)
            $session | Should -BeOfType [string]
        }

        It 'throws when OAuth type receives non-string object' {
            {
                $broker = New-IdleAuthSession -SessionMap @{
                    @{ AuthSessionName = 'EXO' } = @{ AuthSessionType = 'OAuth'; Session = $adCred }
                }
                $broker.AcquireAuthSession('EXO', $null)
            } | Should -Throw '*Expected AuthSessionType=''OAuth'' requires a*string*'
        }

        It 'validates PSRemoting type matches PSCredential' {
            $broker = New-IdleAuthSession -SessionMap @{
                @{ AuthSessionName = 'Remote' } = @{ AuthSessionType = 'PSRemoting'; Session = $adCred }
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

        It 'supports typed DefaultAuthSession' {
            $broker = New-IdleAuthSession -SessionMap @{
                @{ AuthSessionName = 'AD' } = @{ AuthSessionType = 'Credential'; Session = $adCred }
            } -DefaultAuthSession @{ AuthSessionType = 'OAuth'; Session = $exoToken }

            $defaultSession = $broker.AcquireAuthSession('Unknown', $null)
            $defaultSession | Should -BeOfType [string]
            $defaultSession | Should -Be 'mock-oauth-token-12345'
        }

        It 'validates typed DefaultAuthSession' {
            {
                $broker = New-IdleAuthSession -SessionMap @{
                    @{ AuthSessionName = 'AD' } = @{ AuthSessionType = 'Credential'; Session = $adCred }
                } -DefaultAuthSession @{ AuthSessionType = 'Credential'; Session = 'not-a-credential' }

                $broker.AcquireAuthSession('Unknown', $null)
            } | Should -Throw '*Expected AuthSessionType=''Credential''*'
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

        It 'throws with clear error including session name on type mismatch' {
            {
                $broker = New-IdleAuthSession -SessionMap @{
                    @{ AuthSessionName = 'MyCustomSession' } = @{ AuthSessionType = 'Credential'; Session = 'wrong-type' }
                }
                $broker.AcquireAuthSession('MyCustomSession', $null)
            } | Should -Throw '*MyCustomSession*'
        }

        It 'throws when invalid AuthSessionType provided in typed value' {
            {
                New-IdleAuthSession -SessionMap @{
                    @{ AuthSessionName = 'AD' } = @{ AuthSessionType = 'InvalidType'; Session = $adCred }
                }
            } | Should -Throw '*Invalid AuthSessionType*'
        }
    }

    Context 'Backward compatibility' {
        BeforeEach {
            $password = ConvertTo-SecureString 'Password!' -AsPlainText -Force
            $cred = New-Object System.Management.Automation.PSCredential('User', $password)
        }

        It 'legacy untyped SessionMap with -AuthSessionType still works' {
            $broker = New-IdleAuthSession -SessionMap @{
                @{ Role = 'Admin' } = $cred
            } -AuthSessionType 'Credential'

            $session = $broker.AcquireAuthSession('Test', @{ Role = 'Admin' })
            $session | Should -BeOfType [PSCredential]
        }

        It 'legacy untyped DefaultAuthSession with -AuthSessionType still works' {
            $broker = New-IdleAuthSession -SessionMap @{} -DefaultAuthSession $cred -AuthSessionType 'Credential'

            $session = $broker.AcquireAuthSession('Test', $null)
            $session | Should -BeOfType [PSCredential]
        }

        It 'existing tests should continue to work' {
            # This mimics the original test pattern
            $broker = New-IdleAuthSession -SessionMap @{
                @{ Role = 'Tier0' } = $cred
            } -AuthSessionType 'Credential'

            $session = $broker.AcquireAuthSession('TestName', @{ Role = 'Tier0' })
            $session | Should -Not -BeNullOrEmpty
            $session | Should -BeOfType [PSCredential]
        }
    }
}

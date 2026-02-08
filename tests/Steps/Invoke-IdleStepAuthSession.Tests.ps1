#requires -Version 7.0

Describe 'IdLE.Steps - Auth Session Routing' {

    BeforeAll {
        Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '../../src/IdLE/IdLE.psd1') -Force
        Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '../../src/IdLE.Core/IdLE.Core.psd1') -Force
        Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '../../src/IdLE.Steps.Common/IdLE.Steps.Common.psd1') -Force
    }

    Context 'EnsureAttribute - Auth Session Acquisition' {

        It 'acquires auth session when With.AuthSessionName is present' {
            # Arrange
            $testState = [pscustomobject]@{
                SessionAcquired = $false
                AcquiredName = $null
                AcquiredOptions = $null
            }

            $broker = [pscustomobject]@{
                PSTypeName = 'Tests.AuthSessionBroker'
                State = $testState
            }
            $broker | Add-Member -MemberType ScriptMethod -Name AcquireAuthSession -Value {
                param($Name, $Options)
                $this.State.SessionAcquired = $true
                $this.State.AcquiredName = $Name
                $this.State.AcquiredOptions = $Options
                return [PSCredential]::new('testuser', (ConvertTo-SecureString 'testpass' -AsPlainText -Force))
            } -Force

            $mockProvider = [pscustomobject]@{
                PSTypeName = 'Tests.MockProvider'
            }
            $mockProvider | Add-Member -MemberType ScriptMethod -Name EnsureAttribute -Value {
                param($IdentityKey, $Name, $Value, $AuthSession)
                return [pscustomobject]@{
                    PSTypeName = 'IdLE.ProviderResult'
                    Changed = $true
                }
            } -Force

            $context = [pscustomobject]@{
                PSTypeName = 'IdLE.ExecutionContext'
                Providers = @{
                    Identity = $mockProvider
                    AuthSessionBroker = $broker
                }
            }
            $context | Add-Member -MemberType ScriptMethod -Name AcquireAuthSession -Value {
                param($Name, $Options)
                return $this.Providers.AuthSessionBroker.AcquireAuthSession($Name, $Options)
            } -Force

            $step = [pscustomobject]@{
                PSTypeName = 'IdLE.Step'
                Name = 'TestStep'
                Type = 'IdLE.Step.EnsureAttribute'
                With = @{
                    IdentityKey = 'testuser'
                    Name = 'Department'
                    Value = 'IT'
                    AuthSessionName = 'ActiveDirectory'
                    AuthSessionOptions = @{ Role = 'Tier0' }
                }
            }

            # Act
            $result = Invoke-IdleStepEnsureAttribute -Context $context -Step $step

            # Assert
            $result | Should -Not -BeNullOrEmpty
            $result.PSTypeNames | Should -Contain 'IdLE.StepResult'
            $result.Status | Should -Be 'Completed'
            $testState.SessionAcquired | Should -Be $true
            $testState.AcquiredName | Should -Be 'ActiveDirectory'
            $testState.AcquiredOptions.Role | Should -Be 'Tier0'
        }

        It 'does not acquire auth session when With.AuthSessionName is absent' {
            # Arrange
            $sessionAcquired = $false

            $broker = [pscustomobject]@{
                PSTypeName = 'Tests.AuthSessionBroker'
            }
            $broker | Add-Member -MemberType ScriptMethod -Name AcquireAuthSession -Value {
                param($Name, $Options)
                $script:sessionAcquired = $true
                throw "Should not be called"
            } -Force

            $mockProvider = [pscustomobject]@{
                PSTypeName = 'Tests.MockProvider'
            }
            $mockProvider | Add-Member -MemberType ScriptMethod -Name EnsureAttribute -Value {
                param($IdentityKey, $Name, $Value)
                return [pscustomobject]@{
                    PSTypeName = 'IdLE.ProviderResult'
                    Changed = $true
                }
            } -Force

            $context = [pscustomobject]@{
                PSTypeName = 'IdLE.ExecutionContext'
                Providers = @{
                    Identity = $mockProvider
                    AuthSessionBroker = $broker
                }
            }
            $context | Add-Member -MemberType ScriptMethod -Name AcquireAuthSession -Value {
                param($Name, $Options)
                return $this.Providers.AuthSessionBroker.AcquireAuthSession($Name, $Options)
            } -Force

            $step = [pscustomobject]@{
                PSTypeName = 'IdLE.Step'
                Name = 'TestStep'
                Type = 'IdLE.Step.EnsureAttribute'
                With = @{
                    IdentityKey = 'testuser'
                    Name = 'Department'
                    Value = 'IT'
                }
            }

            # Act
            $result = Invoke-IdleStepEnsureAttribute -Context $context -Step $step

            # Assert
            $result | Should -Not -BeNullOrEmpty
            $result.Status | Should -Be 'Completed'
            $sessionAcquired | Should -Be $false
        }

        It 'passes auth session to provider when provider supports AuthSession parameter' {
            # Arrange
            $testState = [pscustomobject]@{
                ReceivedAuthSession = $null
            }

            $broker = [pscustomobject]@{
                PSTypeName = 'Tests.AuthSessionBroker'
            }
            $broker | Add-Member -MemberType ScriptMethod -Name AcquireAuthSession -Value {
                param($Name, $Options)
                return [PSCredential]::new('tier0admin', (ConvertTo-SecureString 'pass123' -AsPlainText -Force))
            } -Force

            $mockProvider = [pscustomobject]@{
                PSTypeName = 'Tests.MockProvider'
                State = $testState
            }
            $mockProvider | Add-Member -MemberType ScriptMethod -Name EnsureAttribute -Value {
                param($IdentityKey, $Name, $Value, $AuthSession)
                $this.State.ReceivedAuthSession = $AuthSession
                return [pscustomobject]@{
                    PSTypeName = 'IdLE.ProviderResult'
                    Changed = $true
                }
            } -Force

            $context = [pscustomobject]@{
                PSTypeName = 'IdLE.ExecutionContext'
                Providers = @{
                    Identity = $mockProvider
                    AuthSessionBroker = $broker
                }
            }
            $context | Add-Member -MemberType ScriptMethod -Name AcquireAuthSession -Value {
                param($Name, $Options)
                return $this.Providers.AuthSessionBroker.AcquireAuthSession($Name, $Options)
            } -Force

            $step = [pscustomobject]@{
                PSTypeName = 'IdLE.Step'
                Name = 'TestStep'
                Type = 'IdLE.Step.EnsureAttribute'
                With = @{
                    IdentityKey = 'testuser'
                    Name = 'Department'
                    Value = 'IT'
                    AuthSessionName = 'ActiveDirectory'
                }
            }

            # Act
            $result = Invoke-IdleStepEnsureAttribute -Context $context -Step $step

            # Assert
            $result | Should -Not -BeNullOrEmpty
            $result.Status | Should -Be 'Completed'
            $testState.ReceivedAuthSession | Should -Not -BeNullOrEmpty
            $testState.ReceivedAuthSession | Should -BeOfType [PSCredential]
            $testState.ReceivedAuthSession.UserName | Should -Be 'tier0admin'
        }

        It 'falls back to legacy signature when provider lacks AuthSession parameter' {
            # Arrange
            $testState = [pscustomobject]@{
                LegacyCallMade = $false
            }

            $broker = [pscustomobject]@{
                PSTypeName = 'Tests.AuthSessionBroker'
            }
            $broker | Add-Member -MemberType ScriptMethod -Name AcquireAuthSession -Value {
                param($Name, $Options)
                return [PSCredential]::new('tier0admin', (ConvertTo-SecureString 'pass123' -AsPlainText -Force))
            } -Force

            # Provider without AuthSession parameter (legacy)
            $mockProvider = [pscustomobject]@{
                PSTypeName = 'Tests.MockProvider'
                State = $testState
            }
            $mockProvider | Add-Member -MemberType ScriptMethod -Name EnsureAttribute -Value {
                param($IdentityKey, $Name, $Value)
                $this.State.LegacyCallMade = $true
                return [pscustomobject]@{
                    PSTypeName = 'IdLE.ProviderResult'
                    Changed = $true
                }
            } -Force

            $context = [pscustomobject]@{
                PSTypeName = 'IdLE.ExecutionContext'
                Providers = @{
                    Identity = $mockProvider
                    AuthSessionBroker = $broker
                }
            }
            $context | Add-Member -MemberType ScriptMethod -Name AcquireAuthSession -Value {
                param($Name, $Options)
                return $this.Providers.AuthSessionBroker.AcquireAuthSession($Name, $Options)
            } -Force

            $step = [pscustomobject]@{
                PSTypeName = 'IdLE.Step'
                Name = 'TestStep'
                Type = 'IdLE.Step.EnsureAttribute'
                With = @{
                    IdentityKey = 'testuser'
                    Name = 'Department'
                    Value = 'IT'
                    AuthSessionName = 'ActiveDirectory'
                }
            }

            # Act
            $result = Invoke-IdleStepEnsureAttribute -Context $context -Step $step

            # Assert
            $result | Should -Not -BeNullOrEmpty
            $result.Status | Should -Be 'Completed'
            $testState.LegacyCallMade | Should -Be $true
        }

        It 'throws when With.AuthSessionOptions is not a hashtable' {
            # Arrange
            $mockProvider = [pscustomobject]@{
                PSTypeName = 'Tests.MockProvider'
            }
            $mockProvider | Add-Member -MemberType ScriptMethod -Name EnsureAttribute -Value {
                param($IdentityKey, $Name, $Value)
                return [pscustomobject]@{
                    PSTypeName = 'IdLE.ProviderResult'
                    Changed = $true
                }
            } -Force

            $context = [pscustomobject]@{
                PSTypeName = 'IdLE.ExecutionContext'
                Providers = @{
                    Identity = $mockProvider
                }
            }

            $step = [pscustomobject]@{
                PSTypeName = 'IdLE.Step'
                Name = 'TestStep'
                Type = 'IdLE.Step.EnsureAttribute'
                With = @{
                    IdentityKey = 'testuser'
                    Name = 'Department'
                    Value = 'IT'
                    AuthSessionName = 'ActiveDirectory'
                    AuthSessionOptions = 'invalid-string'
                }
            }

            # Act & Assert
            { Invoke-IdleStepEnsureAttribute -Context $context -Step $step } |
                Should -Throw '*AuthSessionOptions*hashtable*'
        }

        It 'acquires default auth session when AuthSessionName is absent but broker exists' {
            # Arrange
            $testState = [pscustomobject]@{
                SessionAcquired = $false
                AcquiredName = $null
                AcquiredOptions = $null
            }

            $broker = [pscustomobject]@{
                PSTypeName = 'Tests.AuthSessionBroker'
                State = $testState
            }
            $broker | Add-Member -MemberType ScriptMethod -Name AcquireAuthSession -Value {
                param($Name, $Options)
                $this.State.SessionAcquired = $true
                $this.State.AcquiredName = $Name
                $this.State.AcquiredOptions = $Options
                return [PSCredential]::new('defaultuser', (ConvertTo-SecureString 'defaultpass' -AsPlainText -Force))
            } -Force

            $mockProvider = [pscustomobject]@{
                PSTypeName = 'Tests.MockProvider'
            }
            $mockProvider | Add-Member -MemberType ScriptMethod -Name EnsureAttribute -Value {
                param($IdentityKey, $Name, $Value, $AuthSession)
                return [pscustomobject]@{
                    PSTypeName = 'IdLE.ProviderResult'
                    Changed = $true
                }
            } -Force

            $context = [pscustomobject]@{
                PSTypeName = 'IdLE.ExecutionContext'
                Providers = @{
                    Identity = $mockProvider
                    AuthSessionBroker = $broker
                }
            }
            $context | Add-Member -MemberType ScriptMethod -Name AcquireAuthSession -Value {
                param($Name, $Options)
                return $this.Providers.AuthSessionBroker.AcquireAuthSession($Name, $Options)
            } -Force

            $step = [pscustomobject]@{
                PSTypeName = 'IdLE.Step'
                Name = 'TestStep'
                Type = 'IdLE.Step.EnsureAttribute'
                With = @{
                    IdentityKey = 'testuser'
                    Name = 'Department'
                    Value = 'IT'
                    # No AuthSessionName - should still try to acquire default session
                }
            }

            # Act
            $result = Invoke-IdleStepEnsureAttribute -Context $context -Step $step

            # Assert
            $result | Should -Not -BeNullOrEmpty
            $result.Status | Should -Be 'Completed'
            $testState.SessionAcquired | Should -Be $true
            $testState.AcquiredName | Should -Be ''
            $testState.AcquiredOptions | Should -BeNullOrEmpty
        }

        It 'throws when AuthSessionName is set but no broker is available' {
            # Arrange
            $mockProvider = [pscustomobject]@{
                PSTypeName = 'Tests.MockProvider'
            }
            $mockProvider | Add-Member -MemberType ScriptMethod -Name EnsureAttribute -Value {
                param($IdentityKey, $Name, $Value, $AuthSession)
                return [pscustomobject]@{
                    PSTypeName = 'IdLE.ProviderResult'
                    Changed = $true
                }
            } -Force

            $context = [pscustomobject]@{
                PSTypeName = 'IdLE.ExecutionContext'
                Providers = @{
                    Identity = $mockProvider
                    # No AuthSessionBroker
                }
            }

            $step = [pscustomobject]@{
                PSTypeName = 'IdLE.Step'
                Name = 'TestStep'
                Type = 'IdLE.Step.EnsureAttribute'
                With = @{
                    IdentityKey = 'testuser'
                    Name = 'Department'
                    Value = 'IT'
                    AuthSessionName = 'ActiveDirectory'  # Explicitly set but no broker
                }
            }

            # Act & Assert
            { Invoke-IdleStepEnsureAttribute -Context $context -Step $step } |
                Should -Throw '*AuthSessionName*AcquireAuthSession*'
        }
    }
}

Set-StrictMode -Version Latest

BeforeAll {
    . (Join-Path (Split-Path -Path $PSScriptRoot -Parent) '_testHelpers.ps1')
    Import-IdleTestModule
}

Describe 'Invoke-IdleStepEnsureAttributes (auth session routing)' {
    BeforeEach {
        $script:State = [pscustomobject]@{
            SessionAcquired    = $false
            AcquiredName       = $null
            AcquiredOptions    = $null
            ReceivedAuthSession = $null
            LegacyCallMade     = $false
        }

        $script:Broker = [pscustomobject]@{
            PSTypeName = 'Tests.AuthSessionBroker'
            State      = $script:State
        }
        $script:Broker | Add-Member -MemberType ScriptMethod -Name AcquireAuthSession -Value {
            param($Name, $Options)
            $this.State.SessionAcquired = $true
            $this.State.AcquiredName = $Name
            $this.State.AcquiredOptions = $Options
            return [PSCredential]::new('tier0admin', (ConvertTo-SecureString 'pass123' -AsPlainText -Force))
        } -Force

        $script:Provider = [pscustomobject]@{
            PSTypeName = 'Tests.MockProvider'
            State      = $script:State
        }
        $script:Provider | Add-Member -MemberType ScriptMethod -Name EnsureAttribute -Value {
            param($IdentityKey, $Name, $Value, $AuthSession)
            $this.State.ReceivedAuthSession = $AuthSession
            return [pscustomobject]@{
                PSTypeName = 'IdLE.ProviderResult'
                Changed    = $true
            }
        } -Force

        $script:Context = [pscustomobject]@{
            PSTypeName = 'IdLE.ExecutionContext'
            Providers  = @{
                Identity          = $script:Provider
                AuthSessionBroker = $script:Broker
            }
        }
        $script:Context | Add-Member -MemberType ScriptMethod -Name AcquireAuthSession -Value {
            param($Name, $Options)
            return $this.Providers.AuthSessionBroker.AcquireAuthSession($Name, $Options)
        } -Force

        $script:Handler = 'IdLE.Steps.Common\Invoke-IdleStepEnsureAttributes'

        $script:StepTemplate = [pscustomobject]@{
            PSTypeName = 'IdLE.Step'
            Name       = 'TestStep'
            Type       = 'IdLE.Step.EnsureAttributes'
            With       = @{
                IdentityKey        = 'testuser'
                Attributes         = @{ Department = 'IT' }
                AuthSessionName    = 'ActiveDirectory'
                AuthSessionOptions = @{ Role = 'Tier0' }
            }
        }
    }

    Context 'Auth session acquisition' {
        It 'acquires auth session when AuthSessionName is present' {
            $result = & $script:Handler -Context $script:Context -Step $script:StepTemplate

            $result | Should -Not -BeNullOrEmpty
            $result.PSTypeNames | Should -Contain 'IdLE.StepResult'
            $result.Status | Should -Be 'Completed'
            $script:State.SessionAcquired | Should -Be $true
            $script:State.AcquiredName | Should -Be 'ActiveDirectory'
            $script:State.AcquiredOptions.Role | Should -Be 'Tier0'
        }

        It 'does not acquire auth session when AuthSessionName is absent and provider lacks AuthSession parameter' {
            $script:Provider | Add-Member -MemberType ScriptMethod -Name EnsureAttribute -Value {
                param($IdentityKey, $Name, $Value)
                $this.State.LegacyCallMade = $true
                return [pscustomobject]@{
                    PSTypeName = 'IdLE.ProviderResult'
                    Changed    = $true
                }
            } -Force

            $step = $script:StepTemplate
            $step.With.Remove('AuthSessionName')
            $step.With.Remove('AuthSessionOptions')

            $result = & $script:Handler -Context $script:Context -Step $step

            $result.Status | Should -Be 'Completed'
            $script:State.SessionAcquired | Should -Be $false
        }

        It 'passes auth session to provider when provider supports AuthSession parameter' {
            $result = & $script:Handler -Context $script:Context -Step $script:StepTemplate

            $result | Should -Not -BeNullOrEmpty
            $result.Status | Should -Be 'Completed'
            $script:State.ReceivedAuthSession | Should -Not -BeNullOrEmpty
            $script:State.ReceivedAuthSession | Should -BeOfType [PSCredential]
            $script:State.ReceivedAuthSession.UserName | Should -Be 'tier0admin'
        }

        It 'falls back to legacy signature when provider lacks AuthSession parameter' {
            $script:Provider | Add-Member -MemberType ScriptMethod -Name EnsureAttribute -Value {
                param($IdentityKey, $Name, $Value)
                $this.State.LegacyCallMade = $true
                return [pscustomobject]@{
                    PSTypeName = 'IdLE.ProviderResult'
                    Changed    = $true
                }
            } -Force

            $result = & $script:Handler -Context $script:Context -Step $script:StepTemplate

            $result | Should -Not -BeNullOrEmpty
            $result.Status | Should -Be 'Completed'
            $script:State.LegacyCallMade | Should -Be $true
        }

        It 'throws when AuthSessionOptions is not a hashtable' {
            $step = $script:StepTemplate
            $step.With.AuthSessionOptions = 'invalid-string'

            { & $script:Handler -Context $script:Context -Step $step } |
                Should -Throw '*AuthSessionOptions*hashtable*'
        }

        It 'acquires default auth session when AuthSessionName is absent but broker exists' {
            $step = $script:StepTemplate
            $step.With.Remove('AuthSessionName')
            $step.With.Remove('AuthSessionOptions')

            $result = & $script:Handler -Context $script:Context -Step $step

            $result | Should -Not -BeNullOrEmpty
            $result.Status | Should -Be 'Completed'
            $script:State.SessionAcquired | Should -Be $true
            $script:State.AcquiredName | Should -Be ''
            $script:State.AcquiredOptions | Should -BeNullOrEmpty
        }

        It 'throws when AuthSessionName is set but no broker is available' {
            $context = [pscustomobject]@{
                PSTypeName = 'IdLE.ExecutionContext'
                Providers  = @{ Identity = $script:Provider }
            }

            { & $script:Handler -Context $context -Step $script:StepTemplate } |
                Should -Throw '*AuthSessionName*AcquireAuthSession*'
        }
    }
}

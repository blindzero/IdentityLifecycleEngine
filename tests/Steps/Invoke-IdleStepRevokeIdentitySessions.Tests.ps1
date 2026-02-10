Set-StrictMode -Version Latest

BeforeAll {
    . (Join-Path (Split-Path -Path $PSScriptRoot -Parent) '_testHelpers.ps1')
    Import-IdleTestModule
}

Describe 'Invoke-IdleStepRevokeIdentitySessions (built-in step)' {
    BeforeEach {
        # Create a fake provider with RevokeSessions support
        $script:FakeProvider = [pscustomobject]@{
            PSTypeName = 'IdLE.Provider.FakeWithRevoke'
            CallLog    = @()
        }

        $script:FakeProvider | Add-Member -MemberType ScriptMethod -Name GetCapabilities -Value {
            return @('IdLE.Identity.RevokeSessions')
        }

        $script:FakeProvider | Add-Member -MemberType ScriptMethod -Name RevokeSessions -Value {
            param(
                [Parameter(Mandatory)]
                [string] $IdentityKey,

                [Parameter()]
                [object] $AuthSession
            )

            $this.CallLog += @{
                Method      = 'RevokeSessions'
                IdentityKey = $IdentityKey
                AuthSession = $AuthSession
            }

            return [pscustomobject]@{
                PSTypeName  = 'IdLE.ProviderResult'
                Operation   = 'RevokeSessions'
                IdentityKey = $IdentityKey
                Changed     = $true
            }
        }

        $script:Context = [pscustomobject]@{
            PSTypeName = 'IdLE.ExecutionContext'
            Plan       = $null
            Providers  = @{ Identity = $script:FakeProvider }
            EventSink  = [pscustomobject]@{ WriteEvent = { param($Type, $Message, $StepName, $Data) } }
        }

        $script:Context | Add-Member -MemberType ScriptMethod -Name AcquireAuthSession -Value {
            param($Name, $Options)
            return [pscustomobject]@{
                SessionName = $Name
                Options     = $Options
                Token       = 'fake-auth-token'
            }
        }

        $script:StepTemplate = [pscustomobject]@{
            Name = 'Revoke sessions'
            Type = 'IdLE.Step.RevokeIdentitySessions'
            With = @{
                IdentityKey = 'user@contoso.com'
                Provider    = 'Identity'
            }
        }
    }

    It 'calls provider RevokeSessions method with correct identity key' {
        $step = $script:StepTemplate
        $handler = 'IdLE.Steps.Common\Invoke-IdleStepRevokeIdentitySessions'

        $result = & $handler -Context $script:Context -Step $step

        $result.Status | Should -Be 'Completed'
        $result.Changed | Should -Be $true
        $script:FakeProvider.CallLog.Count | Should -Be 1
        $script:FakeProvider.CallLog[0].IdentityKey | Should -Be 'user@contoso.com'
    }

    It 'returns StepResult with correct shape' {
        $handler = 'IdLE.Steps.Common\Invoke-IdleStepRevokeIdentitySessions'
        $result = & $handler -Context $script:Context -Step $script:StepTemplate

        $result | Should -Not -BeNullOrEmpty
        $result.PSObject.TypeNames[0] | Should -Be 'IdLE.StepResult'
        $result.Name | Should -Be 'Revoke sessions'
        $result.Type | Should -Be 'IdLE.Step.RevokeIdentitySessions'
        $result.Status | Should -Be 'Completed'
        $result.PSObject.Properties.Name | Should -Contain 'Changed'
        $result.PSObject.Properties.Name | Should -Contain 'Error'
        $result.Error | Should -BeNullOrEmpty
    }

    It 'acquires auth session when AuthSessionName is provided' {
        $step = $script:StepTemplate
        $step.With.AuthSessionName = 'MicrosoftGraph'
        $step.With.AuthSessionOptions = @{ Role = 'Admin' }

        $handler = 'IdLE.Steps.Common\Invoke-IdleStepRevokeIdentitySessions'
        $result = & $handler -Context $script:Context -Step $step

        $result.Status | Should -Be 'Completed'
        $script:FakeProvider.CallLog.Count | Should -Be 1
        $script:FakeProvider.CallLog[0].AuthSession | Should -Not -BeNullOrEmpty
        $script:FakeProvider.CallLog[0].AuthSession.SessionName | Should -Be 'MicrosoftGraph'
    }

    It 'throws when With.IdentityKey is missing' {
        $step = $script:StepTemplate
        $step.With.Remove('IdentityKey')

        $handler = 'IdLE.Steps.Common\Invoke-IdleStepRevokeIdentitySessions'
        { & $handler -Context $script:Context -Step $step } | Should -Throw '*requires With.IdentityKey*'
    }

    It 'throws when provider is missing' {
        $script:Context.Providers.Clear()

        $handler = 'IdLE.Steps.Common\Invoke-IdleStepRevokeIdentitySessions'
        { & $handler -Context $script:Context -Step $script:StepTemplate } | Should -Throw '*Provider*was not supplied*'
    }

    It 'throws when provider does not support RevokeSessions method' {
        # Create a provider without RevokeSessions support
        $unsupportedProvider = [pscustomobject]@{
            PSTypeName = 'IdLE.Provider.FakeWithoutRevoke'
        }
        $unsupportedProvider | Add-Member -MemberType ScriptMethod -Name GetCapabilities -Value {
            return @('IdLE.Identity.Read')
        }

        $script:Context.Providers['Identity'] = $unsupportedProvider

        $handler = 'IdLE.Steps.Common\Invoke-IdleStepRevokeIdentitySessions'
        { & $handler -Context $script:Context -Step $script:StepTemplate } | Should -Throw -ErrorId *
    }

    It 'respects Changed flag from provider result' {
        # Modify provider to return Changed=false
        $script:FakeProvider | Add-Member -MemberType ScriptMethod -Name RevokeSessions -Value {
            param($IdentityKey, $AuthSession)
            return [pscustomobject]@{
                PSTypeName  = 'IdLE.ProviderResult'
                Operation   = 'RevokeSessions'
                IdentityKey = $IdentityKey
                Changed     = $false
            }
        } -Force

        $handler = 'IdLE.Steps.Common\Invoke-IdleStepRevokeIdentitySessions'
        $result = & $handler -Context $script:Context -Step $script:StepTemplate

        $result.Changed | Should -Be $false
    }

    It 'uses default provider alias "Identity" when not specified' {
        $step = $script:StepTemplate
        $step.With.Remove('Provider')

        $handler = 'IdLE.Steps.Common\Invoke-IdleStepRevokeIdentitySessions'
        $result = & $handler -Context $script:Context -Step $step

        $result.Status | Should -Be 'Completed'
        $script:FakeProvider.CallLog.Count | Should -Be 1
    }

    It 'supports custom provider alias' {
        $script:Context.Providers['CustomEntra'] = $script:FakeProvider
        $step = $script:StepTemplate
        $step.With.Provider = 'CustomEntra'

        $handler = 'IdLE.Steps.Common\Invoke-IdleStepRevokeIdentitySessions'
        $result = & $handler -Context $script:Context -Step $step

        $result.Status | Should -Be 'Completed'
        $script:FakeProvider.CallLog.Count | Should -Be 1
    }
}

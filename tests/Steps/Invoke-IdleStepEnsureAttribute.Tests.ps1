Set-StrictMode -Version Latest

BeforeAll {
    . (Join-Path (Split-Path -Path $PSScriptRoot -Parent) '_testHelpers.ps1')
    Import-IdleTestModule
}

Describe 'Invoke-IdleStepEnsureAttribute (compatibility wrapper)' {
    BeforeEach {
        # Create a fake provider with EnsureAttribute support
        $script:FakeProvider = [pscustomobject]@{
            PSTypeName = 'IdLE.Provider.FakeIdentity'
            CallLog    = @()
        }

        $script:FakeProvider | Add-Member -MemberType ScriptMethod -Name GetCapabilities -Value {
            return @('IdLE.Identity.Attribute.Ensure')
        }

        $script:FakeProvider | Add-Member -MemberType ScriptMethod -Name EnsureAttribute -Value {
            param(
                [Parameter(Mandatory)]
                [string] $IdentityKey,

                [Parameter(Mandatory)]
                [string] $Name,

                [Parameter(Mandatory)]
                $Value,

                [Parameter()]
                [object] $AuthSession
            )

            $this.CallLog += @{
                Method      = 'EnsureAttribute'
                IdentityKey = $IdentityKey
                Name        = $Name
                Value       = $Value
                AuthSession = $AuthSession
            }

            return [pscustomobject]@{
                PSTypeName  = 'IdLE.ProviderResult'
                Operation   = 'EnsureAttribute'
                IdentityKey = $IdentityKey
                Name        = $Name
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
            Name = 'Ensure Department'
            Type = 'IdLE.Step.EnsureAttribute'
            With = @{
                Provider    = 'Identity'
                IdentityKey = 'user@contoso.com'
                Name        = 'Department'
                Value       = 'IT'
            }
        }
    }

    Context 'Backward compatibility' {
        It 'delegates to plural handler with single attribute' {
            $handler = 'IdLE.Steps.Common\Invoke-IdleStepEnsureAttribute'
            $result = & $handler -Context $script:Context -Step $script:StepTemplate

            $result.Status | Should -Be 'Completed'
            $script:FakeProvider.CallLog.Count | Should -Be 1
            $script:FakeProvider.CallLog[0].Method | Should -Be 'EnsureAttribute'
            $script:FakeProvider.CallLog[0].Name | Should -Be 'Department'
            $script:FakeProvider.CallLog[0].Value | Should -Be 'IT'
        }

        It 'preserves original step type in result' {
            $handler = 'IdLE.Steps.Common\Invoke-IdleStepEnsureAttribute'
            $result = & $handler -Context $script:Context -Step $script:StepTemplate

            $result.Type | Should -Be 'IdLE.Step.EnsureAttribute'
        }

        It 'returns StepResult with correct shape' {
            $handler = 'IdLE.Steps.Common\Invoke-IdleStepEnsureAttribute'
            $result = & $handler -Context $script:Context -Step $script:StepTemplate

            $result | Should -Not -BeNullOrEmpty
            $result.PSObject.TypeNames[0] | Should -Be 'IdLE.StepResult'
            $result.Name | Should -Be 'Ensure Department'
            $result.Status | Should -Be 'Completed'
            $result.PSObject.Properties.Name | Should -Contain 'Changed'
            $result.PSObject.Properties.Name | Should -Contain 'Error'
            $result.Error | Should -BeNullOrEmpty
        }

        It 'preserves Changed flag from provider' {
            # Override provider to return Changed=false
            $script:FakeProvider | Add-Member -MemberType ScriptMethod -Name EnsureAttribute -Value {
                param($IdentityKey, $Name, $Value, $AuthSession)
                return [pscustomobject]@{
                    Changed = $false
                }
            } -Force

            $handler = 'IdLE.Steps.Common\Invoke-IdleStepEnsureAttribute'
            $result = & $handler -Context $script:Context -Step $script:StepTemplate

            $result.Changed | Should -Be $false
        }
    }

    Context 'Validation (singular syntax)' {
        It 'throws when With.IdentityKey is missing' {
            $step = $script:StepTemplate
            $step.With.Remove('IdentityKey')

            $handler = 'IdLE.Steps.Common\Invoke-IdleStepEnsureAttribute'
            { & $handler -Context $script:Context -Step $step } | Should -Throw '*requires With.IdentityKey*'
        }

        It 'throws when With.Name is missing' {
            $step = $script:StepTemplate
            $step.With.Remove('Name')

            $handler = 'IdLE.Steps.Common\Invoke-IdleStepEnsureAttribute'
            { & $handler -Context $script:Context -Step $step } | Should -Throw '*requires With.Name*'
        }

        It 'throws when With.Value is missing' {
            $step = $script:StepTemplate
            $step.With.Remove('Value')

            $handler = 'IdLE.Steps.Common\Invoke-IdleStepEnsureAttribute'
            { & $handler -Context $script:Context -Step $step } | Should -Throw '*requires With.Value*'
        }

        It 'throws when With is not a hashtable' {
            $step = [pscustomobject]@{
                Name = 'Test'
                Type = 'IdLE.Step.EnsureAttribute'
                With = 'not-a-hashtable'
            }

            $handler = 'IdLE.Steps.Common\Invoke-IdleStepEnsureAttribute'
            { & $handler -Context $script:Context -Step $step } | Should -Throw '*requires*With*to be a hashtable*'
        }
    }

    Context 'Authentication support' {
        It 'passes auth session when AuthSessionName is provided' {
            $step = $script:StepTemplate
            $step.With.AuthSessionName = 'MicrosoftGraph'
            $step.With.AuthSessionOptions = @{ Role = 'Admin' }

            $handler = 'IdLE.Steps.Common\Invoke-IdleStepEnsureAttribute'
            $result = & $handler -Context $script:Context -Step $step

            $result.Status | Should -Be 'Completed'
            $script:FakeProvider.CallLog[0].AuthSession | Should -Not -BeNullOrEmpty
            $script:FakeProvider.CallLog[0].AuthSession.SessionName | Should -Be 'MicrosoftGraph'
        }
    }

    Context 'Provider selection' {
        It 'uses default provider alias "Identity" when not specified' {
            $step = $script:StepTemplate
            $step.With.Remove('Provider')

            $handler = 'IdLE.Steps.Common\Invoke-IdleStepEnsureAttribute'
            $result = & $handler -Context $script:Context -Step $step

            $result.Status | Should -Be 'Completed'
            $script:FakeProvider.CallLog.Count | Should -Be 1
        }

        It 'supports custom provider alias' {
            $script:Context.Providers['CustomAD'] = $script:FakeProvider
            $step = $script:StepTemplate
            $step.With.Provider = 'CustomAD'

            $handler = 'IdLE.Steps.Common\Invoke-IdleStepEnsureAttribute'
            $result = & $handler -Context $script:Context -Step $step

            $result.Status | Should -Be 'Completed'
            $script:FakeProvider.CallLog.Count | Should -Be 1
        }
    }
}

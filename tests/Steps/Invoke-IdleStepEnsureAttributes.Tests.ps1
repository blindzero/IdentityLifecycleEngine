Set-StrictMode -Version Latest

BeforeAll {
    . (Join-Path (Split-Path -Path $PSScriptRoot -Parent) '_testHelpers.ps1')
    Import-IdleTestModule
}

Describe 'Invoke-IdleStepEnsureAttributes (built-in step)' {
    BeforeEach {
        # Create a fake provider with EnsureAttribute support (no EnsureAttributes)
        $script:FakeProviderLegacy = [pscustomobject]@{
            PSTypeName = 'IdLE.Provider.FakeLegacy'
            CallLog    = @()
        }

        $script:FakeProviderLegacy | Add-Member -MemberType ScriptMethod -Name GetCapabilities -Value {
            return @('IdLE.Identity.Attribute.Ensure')
        }

        $script:FakeProviderLegacy | Add-Member -MemberType ScriptMethod -Name EnsureAttribute -Value {
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

            # Simulate change for specific attributes
            $changed = ($Name -eq 'Department' -or $Name -eq 'Title')

            return [pscustomobject]@{
                PSTypeName  = 'IdLE.ProviderResult'
                Operation   = 'EnsureAttribute'
                IdentityKey = $IdentityKey
                Name        = $Name
                Changed     = $changed
            }
        }

        # Create a fake provider with EnsureAttributes support (fast path)
        $script:FakeProviderOptimized = [pscustomobject]@{
            PSTypeName = 'IdLE.Provider.FakeOptimized'
            CallLog    = @()
        }

        $script:FakeProviderOptimized | Add-Member -MemberType ScriptMethod -Name GetCapabilities -Value {
            return @('IdLE.Identity.Attribute.Ensure')
        }

        $script:FakeProviderOptimized | Add-Member -MemberType ScriptMethod -Name EnsureAttributes -Value {
            param(
                [Parameter(Mandatory)]
                [string] $IdentityKey,

                [Parameter(Mandatory)]
                [hashtable] $Attributes,

                [Parameter()]
                [object] $AuthSession
            )

            $this.CallLog += @{
                Method      = 'EnsureAttributes'
                IdentityKey = $IdentityKey
                Attributes  = $Attributes
                AuthSession = $AuthSession
            }

            # Simulate some changes
            $attributeResults = @()
            $anyChanged = $false
            foreach ($key in $Attributes.Keys) {
                $changed = ($key -eq 'Department' -or $key -eq 'Title')
                if ($changed) { $anyChanged = $true }
                
                $attributeResults += @{
                    Name    = $key
                    Changed = $changed
                    Error   = $null
                }
            }

            return [pscustomobject]@{
                PSTypeName  = 'IdLE.ProviderResult'
                Operation   = 'EnsureAttributes'
                IdentityKey = $IdentityKey
                Changed     = $anyChanged
                Attributes  = $attributeResults
            }
        }

        $script:Context = [pscustomobject]@{
            PSTypeName = 'IdLE.ExecutionContext'
            Plan       = $null
            Providers  = @{ Identity = $script:FakeProviderLegacy }
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
            Name = 'Ensure multiple attributes'
            Type = 'IdLE.Step.EnsureAttributes'
            With = @{
                Provider    = 'Identity'
                IdentityKey = 'user@contoso.com'
                Attributes  = @{
                    Department = 'IT'
                    Title      = 'Engineer'
                    Office     = 'Building A'
                }
            }
        }
    }

    Context 'Validation' {
        It 'throws when With is missing' {
            $step = [pscustomobject]@{
                Name = 'Test'
                Type = 'IdLE.Step.EnsureAttributes'
            }

            $handler = 'IdLE.Steps.Common\Invoke-IdleStepEnsureAttributes'
            { & $handler -Context $script:Context -Step $step } | Should -Throw '*requires*With*to be a hashtable*'
        }

        It 'throws when With is not a hashtable' {
            $step = [pscustomobject]@{
                Name = 'Test'
                Type = 'IdLE.Step.EnsureAttributes'
                With = 'not-a-hashtable'
            }

            $handler = 'IdLE.Steps.Common\Invoke-IdleStepEnsureAttributes'
            { & $handler -Context $script:Context -Step $step } | Should -Throw '*requires*With*to be a hashtable*'
        }

        It 'throws when With.IdentityKey is missing' {
            $step = $script:StepTemplate
            $step.With.Remove('IdentityKey')

            $handler = 'IdLE.Steps.Common\Invoke-IdleStepEnsureAttributes'
            { & $handler -Context $script:Context -Step $step } | Should -Throw '*requires With.IdentityKey*'
        }

        It 'throws when With.Attributes is missing' {
            $step = $script:StepTemplate
            $step.With.Remove('Attributes')

            $handler = 'IdLE.Steps.Common\Invoke-IdleStepEnsureAttributes'
            { & $handler -Context $script:Context -Step $step } | Should -Throw '*requires With.Attributes*'
        }

        It 'throws when With.Attributes is not a hashtable' {
            $step = $script:StepTemplate
            $step.With.Attributes = 'not-a-hashtable'

            $handler = 'IdLE.Steps.Common\Invoke-IdleStepEnsureAttributes'
            { & $handler -Context $script:Context -Step $step } | Should -Throw '*requires With.Attributes to be a hashtable*'
        }

        It 'throws when With.Attributes is empty' {
            $step = $script:StepTemplate
            $step.With.Attributes = @{}

            $handler = 'IdLE.Steps.Common\Invoke-IdleStepEnsureAttributes'
            { & $handler -Context $script:Context -Step $step } | Should -Throw '*requires With.Attributes to contain at least one attribute*'
        }

        It 'throws when provider is missing' {
            $script:Context.Providers.Clear()

            $handler = 'IdLE.Steps.Common\Invoke-IdleStepEnsureAttributes'
            { & $handler -Context $script:Context -Step $script:StepTemplate } | Should -Throw '*Provider*was not supplied*'
        }
    }

    Context 'Provider fast path (EnsureAttributes method)' {
        BeforeEach {
            $script:Context.Providers['Identity'] = $script:FakeProviderOptimized
        }

        It 'calls EnsureAttributes method once when available' {
            $handler = 'IdLE.Steps.Common\Invoke-IdleStepEnsureAttributes'
            $result = & $handler -Context $script:Context -Step $script:StepTemplate

            $script:FakeProviderOptimized.CallLog.Count | Should -Be 1
            $script:FakeProviderOptimized.CallLog[0].Method | Should -Be 'EnsureAttributes'
            $script:FakeProviderOptimized.CallLog[0].IdentityKey | Should -Be 'user@contoso.com'
            $script:FakeProviderOptimized.CallLog[0].Attributes.Count | Should -Be 3
            $script:FakeProviderOptimized.CallLog[0].Attributes['Department'] | Should -Be 'IT'
            $script:FakeProviderOptimized.CallLog[0].Attributes['Title'] | Should -Be 'Engineer'
            $script:FakeProviderOptimized.CallLog[0].Attributes['Office'] | Should -Be 'Building A'
        }

        It 'returns Changed=true when provider reports changes' {
            $handler = 'IdLE.Steps.Common\Invoke-IdleStepEnsureAttributes'
            $result = & $handler -Context $script:Context -Step $script:StepTemplate

            $result.Changed | Should -Be $true
        }

        It 'includes per-attribute results from provider' {
            $handler = 'IdLE.Steps.Common\Invoke-IdleStepEnsureAttributes'
            $result = & $handler -Context $script:Context -Step $script:StepTemplate

            $result.Data | Should -Not -BeNullOrEmpty
            $result.Data.Attributes | Should -Not -BeNullOrEmpty
            $result.Data.Attributes.Count | Should -Be 3
        }

        It 'passes auth session when AuthSessionName is provided' {
            $step = $script:StepTemplate
            $step.With.AuthSessionName = 'MicrosoftGraph'
            $step.With.AuthSessionOptions = @{ Role = 'Admin' }

            $handler = 'IdLE.Steps.Common\Invoke-IdleStepEnsureAttributes'
            $result = & $handler -Context $script:Context -Step $step

            $script:FakeProviderOptimized.CallLog[0].AuthSession | Should -Not -BeNullOrEmpty
            $script:FakeProviderOptimized.CallLog[0].AuthSession.SessionName | Should -Be 'MicrosoftGraph'
        }
    }

    Context 'Provider fallback (multiple EnsureAttribute calls)' {
        It 'calls EnsureAttribute for each attribute when EnsureAttributes not available' {
            $handler = 'IdLE.Steps.Common\Invoke-IdleStepEnsureAttributes'
            $result = & $handler -Context $script:Context -Step $script:StepTemplate

            $script:FakeProviderLegacy.CallLog.Count | Should -Be 3
            $script:FakeProviderLegacy.CallLog[0].Method | Should -Be 'EnsureAttribute'
            $script:FakeProviderLegacy.CallLog[1].Method | Should -Be 'EnsureAttribute'
            $script:FakeProviderLegacy.CallLog[2].Method | Should -Be 'EnsureAttribute'
        }

        It 'passes correct IdentityKey to each EnsureAttribute call' {
            $handler = 'IdLE.Steps.Common\Invoke-IdleStepEnsureAttributes'
            $result = & $handler -Context $script:Context -Step $script:StepTemplate

            $script:FakeProviderLegacy.CallLog | ForEach-Object {
                $_.IdentityKey | Should -Be 'user@contoso.com'
            }
        }

        It 'passes correct attribute name and value to each call' {
            $handler = 'IdLE.Steps.Common\Invoke-IdleStepEnsureAttributes'
            $result = & $handler -Context $script:Context -Step $script:StepTemplate

            $callsByName = @{}
            $script:FakeProviderLegacy.CallLog | ForEach-Object {
                $callsByName[$_.Name] = $_.Value
            }

            $callsByName['Department'] | Should -Be 'IT'
            $callsByName['Title'] | Should -Be 'Engineer'
            $callsByName['Office'] | Should -Be 'Building A'
        }

        It 'returns Changed=true when any attribute changed' {
            $handler = 'IdLE.Steps.Common\Invoke-IdleStepEnsureAttributes'
            $result = & $handler -Context $script:Context -Step $script:StepTemplate

            # Department and Title return Changed=true in our mock
            $result.Changed | Should -Be $true
        }

        It 'returns Changed=false when no attributes changed' {
            # Override provider to return no changes
            $script:FakeProviderLegacy | Add-Member -MemberType ScriptMethod -Name EnsureAttribute -Value {
                param($IdentityKey, $Name, $Value, $AuthSession)
                
                $this.CallLog += @{
                    Method      = 'EnsureAttribute'
                    IdentityKey = $IdentityKey
                    Name        = $Name
                    Value       = $Value
                }

                return [pscustomobject]@{
                    Changed = $false
                }
            } -Force

            $handler = 'IdLE.Steps.Common\Invoke-IdleStepEnsureAttributes'
            $result = & $handler -Context $script:Context -Step $script:StepTemplate

            $result.Changed | Should -Be $false
        }

        It 'includes per-attribute results in fallback mode' {
            $handler = 'IdLE.Steps.Common\Invoke-IdleStepEnsureAttributes'
            $result = & $handler -Context $script:Context -Step $script:StepTemplate

            $result.Data.Attributes | Should -Not -BeNullOrEmpty
            $result.Data.Attributes.Count | Should -Be 3
            
            # Check that all attributes have result entries
            $attributeNames = $result.Data.Attributes | ForEach-Object { $_.Name }
            $attributeNames | Should -Contain 'Department'
            $attributeNames | Should -Contain 'Title'
            $attributeNames | Should -Contain 'Office'
        }
    }

    Context 'StepResult shape' {
        It 'returns StepResult with correct type and properties' {
            $handler = 'IdLE.Steps.Common\Invoke-IdleStepEnsureAttributes'
            $result = & $handler -Context $script:Context -Step $script:StepTemplate

            $result | Should -Not -BeNullOrEmpty
            $result.PSObject.TypeNames[0] | Should -Be 'IdLE.StepResult'
            $result.Name | Should -Be 'Ensure multiple attributes'
            $result.Type | Should -Be 'IdLE.Step.EnsureAttributes'
            $result.Status | Should -Be 'Completed'
            $result.PSObject.Properties.Name | Should -Contain 'Changed'
            $result.PSObject.Properties.Name | Should -Contain 'Error'
            $result.PSObject.Properties.Name | Should -Contain 'Data'
            $result.Error | Should -BeNullOrEmpty
        }
    }

    Context 'Default provider alias' {
        It 'uses "Identity" as default provider when not specified' {
            $step = $script:StepTemplate
            $step.With.Remove('Provider')

            $handler = 'IdLE.Steps.Common\Invoke-IdleStepEnsureAttributes'
            $result = & $handler -Context $script:Context -Step $step

            $result.Status | Should -Be 'Completed'
            $script:FakeProviderLegacy.CallLog.Count | Should -BeGreaterThan 0
        }

        It 'supports custom provider alias' {
            $script:Context.Providers['CustomAD'] = $script:FakeProviderLegacy
            $step = $script:StepTemplate
            $step.With.Provider = 'CustomAD'

            $handler = 'IdLE.Steps.Common\Invoke-IdleStepEnsureAttributes'
            $result = & $handler -Context $script:Context -Step $step

            $result.Status | Should -Be 'Completed'
            $script:FakeProviderLegacy.CallLog.Count | Should -BeGreaterThan 0
        }
    }
}

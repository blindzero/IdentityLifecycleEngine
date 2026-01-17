BeforeDiscovery {
    . (Join-Path $PSScriptRoot '_testHelpers.ps1')
    Import-IdleTestModule
}

Describe 'Redaction at output boundaries (events, exports, execution results)' {

    InModuleScope 'IdLE.Core' {

        It 'redacts sensitive values before buffering and before sending to external event sinks' {
            $buffer = [System.Collections.Generic.List[object]]::new()

            $received = [System.Collections.Generic.List[object]]::new()

            # IMPORTANT: Write-IdleEvent requires a *method* WriteEvent(event), not a NoteProperty.
            $sink = [pscustomobject]@{
                PSTypeName = 'Tests.EventSink'
            }

            $sink | Add-Member -MemberType ScriptMethod -Name WriteEvent -Value {
                param([Parameter(Mandatory)][object] $evt)
                [void]$received.Add($evt)
            } -Force

            $evt = [pscustomobject]@{
                PSTypeName = 'IdLE.Event'
                Name       = 'Custom'
                Message    = 'hello'
                StepName   = 'Step 1'
                Data       = @{
                    password = 'SuperSecret!'
                    token    = 'abc123'
                    note     = 'ok'
                }
            }

            # Act
            Write-IdleEvent -Event $evt -EventSink $sink -EventBuffer $buffer

            # Original must not be mutated
            $evt.Data.password | Should -Be 'SuperSecret!'
            $evt.Data.token    | Should -Be 'abc123'

            # Buffer gets redacted copy
            @($buffer).Count | Should -Be 1
            $buffer[0].Data.password | Should -Be '[REDACTED]'
            $buffer[0].Data.token    | Should -Be '[REDACTED]'
            $buffer[0].Data.note     | Should -Be 'ok'

            # External sink gets redacted copy
            @($received).Count | Should -Be 1
            $received[0].Data.password | Should -Be '[REDACTED]'
            $received[0].Data.token    | Should -Be '[REDACTED]'
            $received[0].Data.note     | Should -Be 'ok'
        }

        It 'redacts request.input, step.inputs and step.expectedState in plan export JSON' {
            $plan = [pscustomobject]@{
                PSTypeName = 'IdLE.Plan'
                Request    = [pscustomobject]@{
                    PSTypeName     = 'IdLE.LifecycleRequest'
                    Type           = 'Joiner'
                    CorrelationId  = 'corr-001'
                    Actor          = 'tester'
                    Input          = @{
                        userName      = 'alice'
                        password      = 'SuperSecret!'
                        clientSecret  = 'shhh'
                        note          = 'ok'
                    }
                }
                Steps = @(
                    [pscustomobject]@{
                        Name          = 'Step A'
                        Type          = 'EnsureAttribute'
                        With          = @{
                            mail         = 'alice@example.test'
                            accessToken  = 'token-value'
                        }
                        ExpectedState = @{
                            password = 'ShouldNeverAppear'
                            city     = 'Berlin'
                        }
                    }
                )
            }

            $json = Export-IdlePlanObject -Plan $plan

            # Secrets must not appear
            $json | Should -Not -Match 'SuperSecret!'
            $json | Should -Not -Match 'shhh'
            $json | Should -Not -Match 'token-value'
            $json | Should -Not -Match 'ShouldNeverAppear'

            # Marker must appear for each surface
            $json | Should -Match '"password"\s*:\s*"\[REDACTED\]"'
            $json | Should -Match '"clientSecret"\s*:\s*"\[REDACTED\]"'
            $json | Should -Match '"accessToken"\s*:\s*"\[REDACTED\]"'
        }

        It 'redacts provider secrets in the returned execution result (Providers surface)' {
            $plan = [pscustomobject]@{
                PSTypeName = 'IdLE.Plan'
                Request    = [pscustomobject]@{
                    PSTypeName    = 'IdLE.LifecycleRequest'
                    Type          = 'Joiner'
                    CorrelationId = 'corr-002'
                    Actor         = 'tester'
                }
                Steps = @()
            }

            $providers = @{
                Directory = @{
                    endpoint     = 'https://example.test'
                    clientSecret = 'TopSecret'
                    token        = 'abc123'
                }
                Mail = @{
                    apiKey = 'ShouldNotLeak'
                }
            }

            $result = Invoke-IdlePlanObject -Plan $plan -Providers $providers -EventSink $null

            # Original must remain unchanged
            $providers.Directory.clientSecret | Should -Be 'TopSecret'
            $providers.Directory.token        | Should -Be 'abc123'
            $providers.Mail.apiKey            | Should -Be 'ShouldNotLeak'

            # Result must be redacted
            $result.Providers.Directory.clientSecret | Should -Be '[REDACTED]'
            $result.Providers.Directory.token        | Should -Be '[REDACTED]'
            $result.Providers.Mail.apiKey            | Should -Be '[REDACTED]'
        }

        It 'redacts AuthSessionBroker secrets and does not leak broker methods in the returned execution result (Providers surface)' {
            $plan = [pscustomobject]@{
                PSTypeName = 'IdLE.Plan'
                Request    = [pscustomobject]@{
                    PSTypeName    = 'IdLE.LifecycleRequest'
                    Type          = 'Joiner'
                    CorrelationId = 'corr-003'
                    Actor         = 'tester'
                }
                Steps = @()
            }

            $broker = [pscustomobject]@{
                PSTypeName = 'Tests.AuthSessionBroker'
                token      = 'abc123'
                note       = 'ok'
            }

            $broker | Add-Member -MemberType ScriptMethod -Name AcquireAuthSession -Value {
                param([Parameter(Mandatory)][string] $Name, [Parameter(Mandatory)][hashtable] $Options)
                return [pscustomobject]@{
                    PSTypeName = 'IdLE.AuthSession'
                    Kind       = 'Test'
                    Name       = $Name
                }
            } -Force

            $providers = @{
                Directory        = @{
                    clientSecret = 'TopSecret'
                }
                AuthSessionBroker = $broker
            }

            $result = Invoke-IdlePlanObject -Plan $plan -Providers $providers -EventSink $null

            # Original broker must remain unchanged
            $providers.AuthSessionBroker.token | Should -Be 'abc123'
            $providers.AuthSessionBroker.note  | Should -Be 'ok'
            $providers.AuthSessionBroker.PSObject.Methods.Name | Should -Contain 'AcquireAuthSession'

            # Result must be redacted (token) and must not include broker methods
            $result.Providers.AuthSessionBroker.token | Should -Be '[REDACTED]'
            $result.Providers.AuthSessionBroker.note  | Should -Be 'ok'
            $result.Providers.AuthSessionBroker.PSObject.Methods.Name | Should -Not -Contain 'AcquireAuthSession'
        }
    }
}

BeforeDiscovery {
    . (Join-Path $PSScriptRoot '_testHelpers.ps1')
    Import-IdleTestModule
}

Describe 'Issue #48 - Redaction at output boundaries (events, exports, execution results)' {

    InModuleScope 'IdLE.Core' {

        It 'redacts sensitive values before buffering and before sending to external event sinks' {
            $buffer = [System.Collections.Generic.List[object]]::new()

            $received = [System.Collections.Generic.List[object]]::new()
            $sink = [pscustomobject]@{
                PSTypeName = 'Tests.EventSink'
                WriteEvent = {
                    param([Parameter(Mandatory)][object] $evt)
                    [void]$received.Add($evt)
                }
            }

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

            $result = Invoke-IdlePlanObject -Plan $plan -Providers $providers

            # Original must remain unchanged
            $providers.Directory.clientSecret | Should -Be 'TopSecret'
            $providers.Directory.token        | Should -Be 'abc123'
            $providers.Mail.apiKey            | Should -Be 'ShouldNotLeak'

            # Result must be redacted
            $result.Providers.Directory.clientSecret | Should -Be '[REDACTED]'
            $result.Providers.Directory.token        | Should -Be '[REDACTED]'
            $result.Providers.Mail.apiKey            | Should -Be '[REDACTED]'
        }
    }
}

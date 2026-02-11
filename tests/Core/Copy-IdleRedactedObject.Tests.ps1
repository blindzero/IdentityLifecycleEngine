BeforeDiscovery {
    . (Join-Path (Split-Path -Path $PSScriptRoot -Parent) '_testHelpers.ps1')
    Import-IdleTestModule
}

Describe 'Copy-IdleRedactedObject - deterministic redaction utility' {

    InModuleScope 'IdLE.Core' {

        BeforeAll {
            # Guarding to ensure the function is available inside the module scope.
            Get-Command Copy-IdleRedactedObject -ErrorAction Stop | Out-Null
        }

        It 'redacts known keys in nested dictionaries and objects' {
            $input = [ordered]@{
                userName = 'alice'
                password = 'SuperSecret!'
                profile  = [pscustomobject]@{
                    token = 'abc123'
                    city  = 'Berlin'
                }
                meta = @{
                    accessToken = 'token-value'
                    note        = 'ok'
                }
            }

            $copy = Copy-IdleRedactedObject -Value $input

            $copy.userName | Should -Be 'alice'
            $copy.password | Should -Be '[REDACTED]'

            $copy.profile.token | Should -Be '[REDACTED]'
            $copy.profile.city  | Should -Be 'Berlin'

            $copy.meta.accessToken | Should -Be '[REDACTED]'
            $copy.meta.note        | Should -Be 'ok'
        }

        It 'redacts PSCredential and SecureString regardless of key name' {
            $secure = ConvertTo-SecureString -String 'SecretValue' -AsPlainText -Force
            $cred = [pscredential]::new('user', $secure)

            $input = @{
                anyName = $cred
                values  = @(
                    'ok'
                    $secure
                )
            }

            $copy = Copy-IdleRedactedObject -Value $input

            $copy.anyName | Should -Be '[REDACTED]'
            $copy.values[0] | Should -Be 'ok'
            $copy.values[1] | Should -Be '[REDACTED]'
        }

        It 'does not mutate the input object' {
            $input = @{
                password = 'DoNotTouch'
                nested   = @{
                    token = 'StillDoNotTouch'
                }
            }

            $copy = Copy-IdleRedactedObject -Value $input

            # Input must remain unchanged.
            $input.password     | Should -Be 'DoNotTouch'
            $input.nested.token | Should -Be 'StillDoNotTouch'

            # Copy must be redacted.
            $copy.password     | Should -Be '[REDACTED]'
            $copy.nested.token | Should -Be '[REDACTED]'
        }

        It 'uses exact key matching and does not redact partial matches' {
            $input = @{
                password   = 'secret'
                myPassword = 'should-stay'
                Token      = 'value'
                tokenize   = 'should-stay'
            }

            $copy = Copy-IdleRedactedObject -Value $input

            $copy.password   | Should -Be '[REDACTED]'
            $copy.Token      | Should -Be '[REDACTED]'

            $copy.myPassword | Should -Be 'should-stay'
            $copy.tokenize   | Should -Be 'should-stay'
        }

        It 'handles cyclic graphs by replacing the cyclic reference with the redaction marker' {
            $cycle = @{}
            $cycle.self = $cycle

            $copy = Copy-IdleRedactedObject -Value $cycle

            # We cannot represent cycles in a stable export/event model, so we redact the recursive edge.
            $copy.self | Should -Be '[REDACTED]'
        }

        It 'supports a custom redaction marker' {
            $input = @{
                password = 'secret'
            }

            $copy = Copy-IdleRedactedObject -Value $input -RedactionMarker '<redacted>'

            $copy.password | Should -Be '<redacted>'
        }

        It 'redacts AccountPassword key' {
            $input = @{
                userName = 'testuser'
                AccountPassword = 'ProtectedStringValue'
                otherField = 'visible'
            }

            $copy = Copy-IdleRedactedObject -Value $input

            $copy.userName | Should -Be 'testuser'
            $copy.AccountPassword | Should -Be '[REDACTED]'
            $copy.otherField | Should -Be 'visible'
        }

        It 'redacts AccountPasswordAsPlainText key' {
            $input = @{
                userName = 'testuser'
                AccountPasswordAsPlainText = 'PlainTextPassword'
                otherField = 'visible'
            }

            $copy = Copy-IdleRedactedObject -Value $input

            $copy.userName | Should -Be 'testuser'
            $copy.AccountPasswordAsPlainText | Should -Be '[REDACTED]'
            $copy.otherField | Should -Be 'visible'
        }

        It 'redacts both password fields if present in nested structure' {
            $input = @{
                userDetails = @{
                    name = 'alice'
                    AccountPassword = 'SecureValue'
                }
                settings = [pscustomobject]@{
                    AccountPasswordAsPlainText = 'PlainTextValue'
                    enabled = $true
                }
            }

            $copy = Copy-IdleRedactedObject -Value $input

            $copy.userDetails.name | Should -Be 'alice'
            $copy.userDetails.AccountPassword | Should -Be '[REDACTED]'
            $copy.settings.AccountPasswordAsPlainText | Should -Be '[REDACTED]'
            $copy.settings.enabled | Should -Be $true
        }

        It 'redacts GeneratedAccountPasswordPlainText key' {
            $input = @{
                userName = 'testuser'
                GeneratedAccountPasswordPlainText = 'GeneratedPlainTextPassword123!'
                otherField = 'visible'
            }

            $copy = Copy-IdleRedactedObject -Value $input

            $copy.userName | Should -Be 'testuser'
            $copy.GeneratedAccountPasswordPlainText | Should -Be '[REDACTED]'
            $copy.otherField | Should -Be 'visible'
        }

        It 'redacts GeneratedAccountPasswordProtected key' {
            $input = @{
                userName = 'testuser'
                GeneratedAccountPasswordProtected = '76492d1116743f0423413b16050a5345MgB8AHcAYwBVAG0AawBlAEoAZgBMAGIARABlAEIASQBvAA=='
                otherField = 'visible'
            }

            $copy = Copy-IdleRedactedObject -Value $input

            $copy.userName | Should -Be 'testuser'
            $copy.GeneratedAccountPasswordProtected | Should -Be '[REDACTED]'
            $copy.otherField | Should -Be 'visible'
        }

        It 'redacts generated password fields in nested structures' {
            $input = @{
                result = @{
                    IdentityKey = 'user@contoso.com'
                    GeneratedAccountPasswordPlainText = 'PlainPassword'
                    GeneratedAccountPasswordProtected = 'ProtectedPassword'
                    Changed = $true
                }
                metadata = [pscustomobject]@{
                    GeneratedAccountPasswordPlainText = 'AnotherPlain'
                    timestamp = '2024-01-01'
                }
            }

            $copy = Copy-IdleRedactedObject -Value $input

            $copy.result.IdentityKey | Should -Be 'user@contoso.com'
            $copy.result.GeneratedAccountPasswordPlainText | Should -Be '[REDACTED]'
            $copy.result.GeneratedAccountPasswordProtected | Should -Be '[REDACTED]'
            $copy.result.Changed | Should -Be $true
            $copy.metadata.GeneratedAccountPasswordPlainText | Should -Be '[REDACTED]'
            $copy.metadata.timestamp | Should -Be '2024-01-01'
        }
    }
}

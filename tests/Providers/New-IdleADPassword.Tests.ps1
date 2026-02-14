Set-StrictMode -Version Latest

# PSScriptAnalyzer can flag test-only mocks and protected string conversions.
#pragma warning disable PSReviewUnusedParameter
#pragma warning disable PSAvoidUsingPlainTextForPassword
#pragma warning disable PSAvoidUsingConvertToSecureStringWithPlainText

BeforeAll {
    . (Join-Path (Split-Path -Path $PSScriptRoot -Parent) '_testHelpers.ps1')
    Import-IdleTestModule

    $script:TestsRoot = Split-Path -Path $PSScriptRoot -Parent
    $script:RepoRoot = Split-Path -Path $script:TestsRoot -Parent

    # Import AD provider module to access private functions
    $script:AdModulePath = Join-Path -Path $script:RepoRoot -ChildPath 'src\IdLE.Provider.AD\IdLE.Provider.AD.psm1'
    if (-not (Test-Path -LiteralPath $script:AdModulePath -PathType Leaf)) {
        throw "AD provider module not found at: $script:AdModulePath"
    }
    Import-Module $script:AdModulePath -Force
}

Describe 'New-IdleADPassword - Policy-aware password generation' {
    InModuleScope 'IdLE.Provider.AD' {
        BeforeAll {
            # Ensure the function is available
            Get-Command New-IdleADPassword -ErrorAction Stop | Out-Null

            # Mock Get-ADDefaultDomainPasswordPolicy globally for this module scope
            # This cmdlet is from the ActiveDirectory module which may not be available in test environment
            if (-not (Get-Command Get-ADDefaultDomainPasswordPolicy -ErrorAction SilentlyContinue)) {
                function Get-ADDefaultDomainPasswordPolicy {
                    param(
                        [Parameter()]
                        [pscredential]$Credential,
                        [Parameter()]
                        [System.Management.Automation.ActionPreference]$ErrorAction
                    )
                    if ($PSBoundParameters.ContainsKey('Credential')) { $Credential | Out-Null }
                    if ($PSBoundParameters.ContainsKey('ErrorAction')) { $ErrorAction | Out-Null }
                    throw "Not implemented - should be mocked in tests"
                }
            }
        }

        Context 'Password generation with fallback configuration' {
            It 'Generates password with default fallback settings when policy cannot be read' {
                # Mock Get-ADDefaultDomainPasswordPolicy to simulate failure
                Mock Get-ADDefaultDomainPasswordPolicy {
                    throw "Domain policy not available"
                }

                $result = New-IdleADPassword

                # Verify password was generated
                $result.PlainText | Should -Not -BeNullOrEmpty
                $result.SecureString | Should -BeOfType [securestring]
                $result.ProtectedString | Should -Not -BeNullOrEmpty
                $result.UsedPolicy | Should -Be 'Fallback'

                # Verify minimum length (default is 24)
                $result.PlainText.Length | Should -BeGreaterOrEqual 24
            }

            It 'Generates password with custom fallback minimum length' {
                Mock Get-ADDefaultDomainPasswordPolicy {
                    throw "Domain policy not available"
                }

                $result = New-IdleADPassword -FallbackMinLength 32

                $result.PlainText.Length | Should -BeGreaterOrEqual 32
                $result.UsedPolicy | Should -Be 'Fallback'
            }

            It 'Includes uppercase characters when required' {
                Mock Get-ADDefaultDomainPasswordPolicy {
                    throw "Domain policy not available"
                }

                $result = New-IdleADPassword -FallbackRequireUpper $true

                $result.PlainText | Should -Match '[A-Z]'
            }

            It 'Includes lowercase characters when required' {
                Mock Get-ADDefaultDomainPasswordPolicy {
                    throw "Domain policy not available"
                }

                $result = New-IdleADPassword -FallbackRequireLower $true

                $result.PlainText | Should -Match '[a-z]'
            }

            It 'Includes digit characters when required' {
                Mock Get-ADDefaultDomainPasswordPolicy {
                    throw "Domain policy not available"
                }

                $result = New-IdleADPassword -FallbackRequireDigit $true

                $result.PlainText | Should -Match '[0-9]'
            }

            It 'Includes special characters when required' {
                Mock Get-ADDefaultDomainPasswordPolicy {
                    throw "Domain policy not available"
                }

                $result = New-IdleADPassword -FallbackRequireSpecial $true -FallbackSpecialCharSet '!@#$%'

                $result.PlainText | Should -Match '[!@#$%]'
            }

            It 'Uses default special character set when required but set is empty' {
                Mock Get-ADDefaultDomainPasswordPolicy {
                    throw "Domain policy not available"
                }

                # This should not throw and should use default special chars
                $result = New-IdleADPassword -FallbackRequireSpecial $true -FallbackSpecialCharSet ''

                $result.PlainText | Should -Not -BeNullOrEmpty
                # Should contain at least one character from the default set
                $result.PlainText | Should -Match '[!@#$%&*+\-_=?]'
            }

            It 'Generates password with all character classes when all requirements are true' {
                Mock Get-ADDefaultDomainPasswordPolicy {
                    throw "Domain policy not available"
                }

                $result = New-IdleADPassword `
                    -FallbackRequireUpper $true `
                    -FallbackRequireLower $true `
                    -FallbackRequireDigit $true `
                    -FallbackRequireSpecial $true

                $result.PlainText | Should -Match '[A-Z]'
                $result.PlainText | Should -Match '[a-z]'
                $result.PlainText | Should -Match '[0-9]'
                $result.PlainText | Should -Match '[!@#$%&*+\-_=?]'
            }
        }

        Context 'Password generation with domain policy' {
            It 'Uses domain policy when available' {
                # Mock Get-ADDefaultDomainPasswordPolicy to return a policy
                Mock Get-ADDefaultDomainPasswordPolicy {
                    return [pscustomobject]@{
                        MinPasswordLength = 12
                        ComplexityEnabled = $true
                    }
                }

                $result = New-IdleADPassword

                $result.PlainText.Length | Should -BeGreaterOrEqual 12
                $result.UsedPolicy | Should -Be 'DomainPolicy'
            }

            It 'Enforces fallback as minimum baseline when domain policy allows shorter passwords' {
                Mock Get-ADDefaultDomainPasswordPolicy {
                    return [pscustomobject]@{
                        MinPasswordLength = 8
                        ComplexityEnabled = $false
                    }
                }

                $result = New-IdleADPassword -FallbackMinLength 24

                # Should use the higher of the two (24 from fallback)
                $result.PlainText.Length | Should -BeGreaterOrEqual 24
                $result.UsedPolicy | Should -Be 'DomainPolicy'
            }

            It 'Requires all character classes when domain complexity is enabled' {
                Mock Get-ADDefaultDomainPasswordPolicy {
                    return [pscustomobject]@{
                        MinPasswordLength = 10
                        ComplexityEnabled = $true
                    }
                }

                $result = New-IdleADPassword

                $result.PlainText | Should -Match '[A-Z]'
                $result.PlainText | Should -Match '[a-z]'
                $result.PlainText | Should -Match '[0-9]'
                $result.PlainText | Should -Match '[!@#$%&*+\-_=?]'
            }

            It 'Respects domain policy minimum length when higher than fallback' {
                Mock Get-ADDefaultDomainPasswordPolicy {
                    return [pscustomobject]@{
                        MinPasswordLength = 30
                        ComplexityEnabled = $false
                    }
                }

                $result = New-IdleADPassword -FallbackMinLength 24

                $result.PlainText.Length | Should -BeGreaterOrEqual 30
            }
        }

        Context 'Password output formats' {
            It 'Returns PlainText as string' {
                Mock Get-ADDefaultDomainPasswordPolicy {
                    throw "Domain policy not available"
                }

                $result = New-IdleADPassword

                $result.PlainText | Should -BeOfType [string]
                $result.PlainText | Should -Not -BeNullOrEmpty
            }

            It 'Returns SecureString that can be converted back' {
                Mock Get-ADDefaultDomainPasswordPolicy {
                    throw "Domain policy not available"
                }

                $result = New-IdleADPassword

                $result.SecureString | Should -BeOfType [securestring]
                
                # Verify it can be converted back to plaintext
                $plainFromSecure = [pscredential]::new('x', $result.SecureString).GetNetworkCredential().Password
                $plainFromSecure | Should -Be $result.PlainText
            }

            It 'Returns ProtectedString that can be converted to SecureString' {
                Mock Get-ADDefaultDomainPasswordPolicy {
                    throw "Domain policy not available"
                }

                $result = New-IdleADPassword

                $result.ProtectedString | Should -Not -BeNullOrEmpty
                
                # Verify it can be converted to SecureString
                #pragma warning disable PSAvoidUsingConvertToSecureStringWithPlainText
                { ConvertTo-SecureString -String $result.ProtectedString } | Should -Not -Throw
                #pragma warning restore PSAvoidUsingConvertToSecureStringWithPlainText
            }

            It 'ProtectedString round-trips correctly' {
                Mock Get-ADDefaultDomainPasswordPolicy {
                    throw "Domain policy not available"
                }

                $result = New-IdleADPassword

                # Convert ProtectedString -> SecureString -> PlainText
                #pragma warning disable PSAvoidUsingConvertToSecureStringWithPlainText
                $secure = ConvertTo-SecureString -String $result.ProtectedString
                #pragma warning restore PSAvoidUsingConvertToSecureStringWithPlainText
                $plain = [pscredential]::new('x', $secure).GetNetworkCredential().Password
                
                $plain | Should -Be $result.PlainText
            }
        }

        Context 'Edge cases and validation' {
            It 'Enforces minimum AD password length of 8' {
                Mock Get-ADDefaultDomainPasswordPolicy {
                    return [pscustomobject]@{
                        MinPasswordLength = 4
                        ComplexityEnabled = $false
                    }
                }

                $result = New-IdleADPassword -FallbackMinLength 4

                # Should be at least 8 (AD minimum)
                $result.PlainText.Length | Should -BeGreaterOrEqual 8
            }

            It 'Generates different passwords on each call' {
                Mock Get-ADDefaultDomainPasswordPolicy {
                    throw "Domain policy not available"
                }

                $result1 = New-IdleADPassword
                $result2 = New-IdleADPassword

                $result1.PlainText | Should -Not -Be $result2.PlainText
            }

            It 'Accepts credential parameter without error' {
                Mock Get-ADDefaultDomainPasswordPolicy {
                    param([pscredential]$Credential)
                    if ($PSBoundParameters.ContainsKey('Credential')) { $Credential | Out-Null }
                    return [pscustomobject]@{
                        MinPasswordLength = 12
                        ComplexityEnabled = $true
                    }
                }

                $secure = [System.Security.SecureString]::new()
                foreach ($ch in 'pass'.ToCharArray()) {
                    $secure.AppendChar($ch)
                }
                $secure.MakeReadOnly()

                $fakeCred = [pscredential]::new('user', $secure)
                
                { New-IdleADPassword -Credential $fakeCred } | Should -Not -Throw
            }
        }
    }
}

#pragma warning restore PSAvoidUsingConvertToSecureStringWithPlainText
#pragma warning restore PSAvoidUsingPlainTextForPassword
#pragma warning restore PSReviewUnusedParameter

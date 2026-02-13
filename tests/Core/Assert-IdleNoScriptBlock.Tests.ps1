Set-StrictMode -Version Latest

BeforeAll {
    . (Join-Path (Split-Path -Path $PSScriptRoot -Parent) '_testHelpers.ps1')
    Import-IdleTestModule
}

Describe 'Assert-IdleNoScriptBlock' {
    Context 'Valid data-only inputs' {
        It 'accepts null input' {
            { Assert-IdleNoScriptBlock -InputObject $null -Path 'Test' } | Should -Not -Throw
        }

        It 'accepts scalar values' {
            { Assert-IdleNoScriptBlock -InputObject 'text' -Path 'Test' } | Should -Not -Throw
            { Assert-IdleNoScriptBlock -InputObject 42 -Path 'Test' } | Should -Not -Throw
            { Assert-IdleNoScriptBlock -InputObject $true -Path 'Test' } | Should -Not -Throw
        }

        It 'accepts simple hashtable' {
            $data = @{
                Mode = 'Enabled'
                Message = 'Out of office'
                Count = 5
            }
            { Assert-IdleNoScriptBlock -InputObject $data -Path 'Config' } | Should -Not -Throw
        }

        It 'accepts nested hashtable' {
            $data = @{
                Level1 = @{
                    Level2 = @{
                        Value = 'deep'
                    }
                }
            }
            { Assert-IdleNoScriptBlock -InputObject $data -Path 'Nested' } | Should -Not -Throw
        }

        It 'accepts arrays' {
            $data = @('one', 'two', 'three')
            { Assert-IdleNoScriptBlock -InputObject $data -Path 'Array' } | Should -Not -Throw
        }

        It 'accepts arrays of hashtables' {
            $data = @(
                @{ Name = 'First'; Value = 1 }
                @{ Name = 'Second'; Value = 2 }
            )
            { Assert-IdleNoScriptBlock -InputObject $data -Path 'Items' } | Should -Not -Throw
        }

        It 'accepts PSCustomObject' {
            $data = [pscustomobject]@{
                Property1 = 'value1'
                Property2 = 42
            }
            { Assert-IdleNoScriptBlock -InputObject $data -Path 'Object' } | Should -Not -Throw
        }

        It 'accepts nested PSCustomObject' {
            $data = [pscustomobject]@{
                Outer = [pscustomobject]@{
                    Inner = 'value'
                }
            }
            { Assert-IdleNoScriptBlock -InputObject $data -Path 'Object' } | Should -Not -Throw
        }
    }

    Context 'ScriptBlock detection' {
        It 'rejects direct ScriptBlock' {
            $block = { Write-Host "bad" }
            { Assert-IdleNoScriptBlock -InputObject $block -Path 'Direct' } |
                Should -Throw -ExceptionType ([System.ArgumentException]) -ExpectedMessage '*ScriptBlocks are not allowed*Direct*'
        }

        It 'rejects ScriptBlock in hashtable' {
            $data = @{
                Good = 'value'
                Bad = { Write-Host "malicious" }
            }
            { Assert-IdleNoScriptBlock -InputObject $data -Path 'Config' } |
                Should -Throw -ExceptionType ([System.ArgumentException]) -ExpectedMessage '*ScriptBlocks are not allowed*Config.Bad*'
        }

        It 'rejects ScriptBlock in nested hashtable' {
            $data = @{
                Level1 = @{
                    Level2 = @{
                        Code = { Get-Process }
                    }
                }
            }
            { Assert-IdleNoScriptBlock -InputObject $data -Path 'Nested' } |
                Should -Throw -ExceptionType ([System.ArgumentException]) -ExpectedMessage '*ScriptBlocks are not allowed*Nested.Level1.Level2.Code*'
        }

        It 'rejects ScriptBlock in array' {
            $data = @(
                'normal',
                { Write-Host "bad" },
                'another'
            )
            { Assert-IdleNoScriptBlock -InputObject $data -Path 'Array' } |
                Should -Throw -ExceptionType ([System.ArgumentException])
            
            try {
                Assert-IdleNoScriptBlock -InputObject $data -Path 'Array'
            }
            catch {
                $_.Exception.Message | Should -Match 'Array\[1\]'
            }
        }

        It 'rejects ScriptBlock in PSCustomObject' {
            $data = [pscustomobject]@{
                SafeProperty = 'value'
                UnsafeProperty = { Write-Host "code" }
            }
            { Assert-IdleNoScriptBlock -InputObject $data -Path 'Object' } |
                Should -Throw -ExceptionType ([System.ArgumentException]) -ExpectedMessage '*ScriptBlocks are not allowed*Object.UnsafeProperty*'
        }

        It 'rejects ScriptBlock deeply nested in complex structure' {
            $data = @{
                Items = @(
                    @{
                        Name = 'Item1'
                        Properties = [pscustomobject]@{
                            Setting = 'safe'
                        }
                    }
                    @{
                        Name = 'Item2'
                        Properties = [pscustomobject]@{
                            Action = { Invoke-Command }
                        }
                    }
                )
            }
            { Assert-IdleNoScriptBlock -InputObject $data -Path 'Data' } |
                Should -Throw -ExceptionType ([System.ArgumentException])
            
            try {
                Assert-IdleNoScriptBlock -InputObject $data -Path 'Data'
            }
            catch {
                $_.Exception.Message | Should -Match 'Data\.Items\[1\]\.Properties\.Action'
            }
        }
    }

    Context 'Trusted type exemptions' {
        It 'allows IdLE.AuthSessionBroker with internal ScriptBlock' {
            $broker = [pscustomobject]@{
                PSTypeName = 'IdLE.AuthSessionBroker'
                ValidateAuthSession = { param($s) return $true }
            }
            $broker.PSObject.TypeNames.Insert(0, 'IdLE.AuthSessionBroker')

            { Assert-IdleNoScriptBlock -InputObject $broker -Path 'Broker' } | Should -Not -Throw
        }
    }

    Context 'Path reporting' {
        It 'includes correct path in error message for top-level ScriptBlock' {
            $block = { Write-Host "test" }
            try {
                Assert-IdleNoScriptBlock -InputObject $block -Path 'TopLevel'
                throw "Should have thrown"
            }
            catch {
                $_.Exception.Message | Should -BeLike '*TopLevel*'
            }
        }

        It 'includes correct path in error message for nested ScriptBlock' {
            $data = @{
                Outer = @{
                    Middle = @{
                        Inner = { Write-Host "nested" }
                    }
                }
            }
            try {
                Assert-IdleNoScriptBlock -InputObject $data -Path 'Root'
                throw "Should have thrown"
            }
            catch {
                $_.Exception.Message | Should -BeLike '*Root.Outer.Middle.Inner*'
            }
        }
    }
}

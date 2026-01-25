BeforeDiscovery {
    . (Join-Path $PSScriptRoot '_testHelpers.ps1')
    Import-IdleTestModule
}

BeforeAll {
    . (Join-Path $PSScriptRoot '_testHelpers.ps1')
    Import-IdleTestModule
}

Describe 'Assert-IdleExecutionOptions' {

    It 'accepts null ExecutionOptions' {
        { Assert-IdleExecutionOptions -ExecutionOptions $null } | Should -Not -Throw
    }

    It 'accepts an empty hashtable' {
        { Assert-IdleExecutionOptions -ExecutionOptions @{} } | Should -Not -Throw
    }

    It 'rejects ExecutionOptions that is not a hashtable' {
        { Assert-IdleExecutionOptions -ExecutionOptions 'invalid' } | Should -Throw -ExpectedMessage '*must be a hashtable or IDictionary*'
    }

    It 'rejects ScriptBlocks in ExecutionOptions' {
        $opts = @{
            SomeKey = { Write-Host 'test' }
        }
        { Assert-IdleExecutionOptions -ExecutionOptions $opts } | Should -Throw -ExpectedMessage '*ScriptBlocks are not allowed*'
    }

    It 'accepts valid RetryProfiles' {
        $opts = @{
            RetryProfiles = @{
                Default = @{
                    MaxAttempts              = 3
                    InitialDelayMilliseconds = 200
                    BackoffFactor            = 2.0
                    MaxDelayMilliseconds     = 5000
                    JitterRatio              = 0.2
                }
            }
            DefaultRetryProfile = 'Default'
        }
        { Assert-IdleExecutionOptions -ExecutionOptions $opts } | Should -Not -Throw
    }

    It 'rejects invalid profile key pattern' {
        $opts = @{
            RetryProfiles = @{
                'Invalid Key!' = @{ MaxAttempts = 3 }
            }
        }
        { Assert-IdleExecutionOptions -ExecutionOptions $opts } | Should -Throw -ExpectedMessage '*Invalid Key!*is invalid*'
    }

    It 'rejects MaxAttempts outside valid range' {
        $opts = @{
            RetryProfiles = @{
                Default = @{ MaxAttempts = 11 }
            }
        }
        { Assert-IdleExecutionOptions -ExecutionOptions $opts } | Should -Throw -ExpectedMessage '*MaxAttempts must be an integer between 0 and 10*'
    }

    It 'rejects InitialDelayMilliseconds outside valid range' {
        $opts = @{
            RetryProfiles = @{
                Default = @{ InitialDelayMilliseconds = 70000 }
            }
        }
        { Assert-IdleExecutionOptions -ExecutionOptions $opts } | Should -Throw -ExpectedMessage '*InitialDelayMilliseconds must be an integer between 0 and 60000*'
    }

    It 'rejects BackoffFactor less than 1.0' {
        $opts = @{
            RetryProfiles = @{
                Default = @{ BackoffFactor = 0.5 }
            }
        }
        { Assert-IdleExecutionOptions -ExecutionOptions $opts } | Should -Throw -ExpectedMessage '*BackoffFactor must be a number >= 1.0*'
    }

    It 'rejects MaxDelayMilliseconds outside valid range' {
        $opts = @{
            RetryProfiles = @{
                Default = @{ MaxDelayMilliseconds = 400000 }
            }
        }
        { Assert-IdleExecutionOptions -ExecutionOptions $opts } | Should -Throw -ExpectedMessage '*MaxDelayMilliseconds must be an integer between 0 and 300000*'
    }

    It 'rejects MaxDelayMilliseconds less than InitialDelayMilliseconds' {
        $opts = @{
            RetryProfiles = @{
                Default = @{
                    InitialDelayMilliseconds = 5000
                    MaxDelayMilliseconds     = 1000
                }
            }
        }
        { Assert-IdleExecutionOptions -ExecutionOptions $opts } | Should -Throw -ExpectedMessage '*MaxDelayMilliseconds*must be >= InitialDelayMilliseconds*'
    }

    It 'rejects JitterRatio outside valid range' {
        $opts = @{
            RetryProfiles = @{
                Default = @{ JitterRatio = 1.5 }
            }
        }
        { Assert-IdleExecutionOptions -ExecutionOptions $opts } | Should -Throw -ExpectedMessage '*JitterRatio must be a number between 0.0 and 1.0*'
    }

    It 'rejects DefaultRetryProfile that does not exist in RetryProfiles' {
        $opts = @{
            RetryProfiles = @{
                Default = @{ MaxAttempts = 3 }
            }
            DefaultRetryProfile = 'Unknown'
        }
        { Assert-IdleExecutionOptions -ExecutionOptions $opts } | Should -Throw -ExpectedMessage '*DefaultRetryProfile*Unknown*does not exist*'
    }

    It 'accepts DefaultRetryProfile that exists in RetryProfiles' {
        $opts = @{
            RetryProfiles = @{
                Default = @{ MaxAttempts = 3 }
                Custom  = @{ MaxAttempts = 5 }
            }
            DefaultRetryProfile = 'Custom'
        }
        { Assert-IdleExecutionOptions -ExecutionOptions $opts } | Should -Not -Throw
    }
}

Describe 'Resolve-IdleStepRetryParameters' {

    It 'returns engine defaults when ExecutionOptions is null' {
        $step = @{ Name = 'TestStep'; Type = 'Test' }
        $result = Resolve-IdleStepRetryParameters -Step $step -ExecutionOptions $null

        $result.MaxAttempts | Should -Be 3
        $result.InitialDelayMilliseconds | Should -Be 250
        $result.BackoffFactor | Should -Be 2.0
        $result.MaxDelayMilliseconds | Should -Be 5000
        $result.JitterRatio | Should -Be 0.2
    }

    It 'returns engine defaults when ExecutionOptions has no RetryProfiles' {
        $step = @{ Name = 'TestStep'; Type = 'Test' }
        $opts = @{}
        $result = Resolve-IdleStepRetryParameters -Step $step -ExecutionOptions $opts

        $result.MaxAttempts | Should -Be 3
        $result.InitialDelayMilliseconds | Should -Be 250
    }

    It 'returns profile when step specifies RetryProfile' {
        $step = @{
            Name         = 'TestStep'
            Type         = 'Test'
            RetryProfile = 'Custom'
        }
        $opts = @{
            RetryProfiles = @{
                Custom = @{
                    MaxAttempts              = 6
                    InitialDelayMilliseconds = 500
                }
            }
        }
        $result = Resolve-IdleStepRetryParameters -Step $step -ExecutionOptions $opts

        $result.MaxAttempts | Should -Be 6
        $result.InitialDelayMilliseconds | Should -Be 500
        $result.BackoffFactor | Should -Be 2.0  # Default
    }

    It 'returns default profile when step does not specify RetryProfile' {
        $step = @{
            Name = 'TestStep'
            Type = 'Test'
        }
        $opts = @{
            RetryProfiles = @{
                Default = @{
                    MaxAttempts = 5
                }
                Custom  = @{
                    MaxAttempts = 10
                }
            }
            DefaultRetryProfile = 'Default'
        }
        $result = Resolve-IdleStepRetryParameters -Step $step -ExecutionOptions $opts

        $result.MaxAttempts | Should -Be 5
    }

    It 'throws when step references unknown RetryProfile' {
        $step = @{
            Name         = 'TestStep'
            Type         = 'Test'
            RetryProfile = 'Unknown'
        }
        $opts = @{
            RetryProfiles = @{
                Default = @{ MaxAttempts = 3 }
            }
        }
        { Resolve-IdleStepRetryParameters -Step $step -ExecutionOptions $opts } | Should -Throw -ExpectedMessage '*references unknown RetryProfile*Unknown*'
    }

    It 'works with PSCustomObject steps' {
        $step = [pscustomobject]@{
            Name         = 'TestStep'
            Type         = 'Test'
            RetryProfile = 'Custom'
        }
        $opts = @{
            RetryProfiles = @{
                Custom = @{
                    MaxAttempts = 7
                }
            }
        }
        $result = Resolve-IdleStepRetryParameters -Step $step -ExecutionOptions $opts

        $result.MaxAttempts | Should -Be 7
    }
}

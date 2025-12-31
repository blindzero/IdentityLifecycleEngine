BeforeDiscovery {
    $repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
    Import-Module (Join-Path $repoRoot 'src/IdLE/IdLE.psd1') -Force -ErrorAction Stop
}

Describe 'Condition DSL (schema + evaluator)' {

    InModuleScope 'IdLE.Core' {

        BeforeAll {
            # Guarding to ensure the functions are available.
            Get-Command Test-IdleConditionSchema -ErrorAction Stop | Out-Null
            Get-Command Test-IdleCondition -ErrorAction Stop | Out-Null
        }

        Describe 'Test-IdleConditionSchema' {

            It 'accepts an Equals operator with Path + Value' {
                $condition = @{
                    Equals = @{
                        Path  = 'Plan.LifecycleEvent'
                        Value = 'Joiner'
                    }
                }

                $errors = Test-IdleConditionSchema -Condition $condition -StepName 'Demo'
                $errors.Count | Should -Be 0
            }

            It 'accepts a nested All group with multiple conditions' {
                $condition = @{
                    All = @(
                        @{ Equals = @{ Path = 'Plan.LifecycleEvent'; Value = 'Joiner' } }
                        @{ Exists = @{ Path = 'Plan.LifecycleEvent' } }
                    )
                }

                $errors = Test-IdleConditionSchema -Condition $condition -StepName 'Demo'
                $errors.Count | Should -Be 0
            }

            It 'accepts Exists as short form string path' {
                $condition = @{
                    Exists = 'Plan.LifecycleEvent'
                }

                $errors = Test-IdleConditionSchema -Condition $condition -StepName 'Demo'
                $errors.Count | Should -Be 0
            }

            It 'accepts In operator with Values as array' {
                $condition = @{
                    In = @{
                        Path   = 'Plan.LifecycleEvent'
                        Values = @('Joiner', 'Mover')
                    }
                }

                $errors = Test-IdleConditionSchema -Condition $condition -StepName 'Demo'
                $errors.Count | Should -Be 0
            }

            It 'rejects unknown keys' {
                $condition = @{
                    Equals = @{
                        Path  = 'Plan.LifecycleEvent'
                        Value = 'Joiner'
                    }
                    Foo = 'Bar'
                }

                $errors = Test-IdleConditionSchema -Condition $condition -StepName 'Demo'
                $errors.Count | Should -BeGreaterThan 0
            }

            It 'rejects nodes that define both group and operator' {
                $condition = @{
                    All = @(
                        @{
                            Equals = @{ Path = 'Plan.LifecycleEvent'; Value = 'Joiner' }
                            Any    = @()
                        }
                    )
                }

                $errors = Test-IdleConditionSchema -Condition $condition -StepName 'Demo'
                $errors.Count | Should -BeGreaterThan 0
            }

            It 'rejects group nodes with empty children' {
                $condition = @{
                    Any = @()
                }

                $errors = Test-IdleConditionSchema -Condition $condition -StepName 'Demo'
                $errors.Count | Should -BeGreaterThan 0
            }

            It 'rejects Equals with missing Path' {
                $condition = @{
                    Equals = @{
                        Value = 'Joiner'
                    }
                }

                $errors = Test-IdleConditionSchema -Condition $condition -StepName 'Demo'
                $errors.Count | Should -BeGreaterThan 0
            }

            It 'rejects In with missing Values' {
                $condition = @{
                    In = @{
                        Path = 'Plan.LifecycleEvent'
                    }
                }

                $errors = Test-IdleConditionSchema -Condition $condition -StepName 'Demo'
                $errors.Count | Should -BeGreaterThan 0
            }
        }

        Describe 'Test-IdleCondition' {

            It 'returns true when Equals matches' {
                $context = [pscustomobject]@{
                    Plan = [pscustomobject]@{
                        LifecycleEvent = 'Joiner'
                    }
                }

                $condition = @{
                    Equals = @{
                        Path  = 'Plan.LifecycleEvent'
                        Value = 'Joiner'
                    }
                }

                (Test-IdleCondition -Condition $condition -Context $context) | Should -BeTrue
            }

            It 'returns false when Equals does not match' {
                $context = [pscustomobject]@{
                    Plan = [pscustomobject]@{
                        LifecycleEvent = 'Joiner'
                    }
                }

                $condition = @{
                    Equals = @{
                        Path  = 'Plan.LifecycleEvent'
                        Value = 'Leaver'
                    }
                }

                (Test-IdleCondition -Condition $condition -Context $context) | Should -BeFalse
            }

            It 'supports context. prefix in paths' {
                $context = [pscustomobject]@{
                    Plan = [pscustomobject]@{
                        LifecycleEvent = 'Joiner'
                    }
                }

                $condition = @{
                    Equals = @{
                        Path  = 'context.Plan.LifecycleEvent'
                        Value = 'Joiner'
                    }
                }

                (Test-IdleCondition -Condition $condition -Context $context) | Should -BeTrue
            }

            It 'returns true when Exists finds a non-null value' {
                $context = [pscustomobject]@{
                    Plan = [pscustomobject]@{
                        LifecycleEvent = 'Joiner'
                    }
                }

                $condition = @{
                    Exists = @{
                        Path = 'Plan.LifecycleEvent'
                    }
                }

                (Test-IdleCondition -Condition $condition -Context $context) | Should -BeTrue
            }

            It 'returns false when Exists cannot resolve the path' {
                $context = [pscustomobject]@{
                    Plan = [pscustomobject]@{
                        LifecycleEvent = 'Joiner'
                    }
                }

                $condition = @{
                    Exists = @{
                        Path = 'Plan.DoesNotExist'
                    }
                }

                (Test-IdleCondition -Condition $condition -Context $context) | Should -BeFalse
            }

            It 'returns true when In matches a candidate value' {
                $context = [pscustomobject]@{
                    Plan = [pscustomobject]@{
                        LifecycleEvent = 'Joiner'
                    }
                }

                $condition = @{
                    In = @{
                        Path   = 'Plan.LifecycleEvent'
                        Values = @('Joiner', 'Mover')
                    }
                }

                (Test-IdleCondition -Condition $condition -Context $context) | Should -BeTrue
            }

            It 'evaluates All as logical AND' {
                $context = [pscustomobject]@{
                    Plan = [pscustomobject]@{
                        LifecycleEvent = 'Joiner'
                    }
                }

                $condition = @{
                    All = @(
                        @{ Equals = @{ Path = 'Plan.LifecycleEvent'; Value = 'Joiner' } }
                        @{ NotEquals = @{ Path = 'Plan.LifecycleEvent'; Value = 'Leaver' } }
                    )
                }

                (Test-IdleCondition -Condition $condition -Context $context) | Should -BeTrue
            }

            It 'evaluates Any as logical OR' {
                $context = [pscustomobject]@{
                    Plan = [pscustomobject]@{
                        LifecycleEvent = 'Joiner'
                    }
                }

                $condition = @{
                    Any = @(
                        @{ Equals = @{ Path = 'Plan.LifecycleEvent'; Value = 'Leaver' } }
                        @{ Equals = @{ Path = 'Plan.LifecycleEvent'; Value = 'Joiner' } }
                    )
                }

                (Test-IdleCondition -Condition $condition -Context $context) | Should -BeTrue
            }

            It 'evaluates None as logical NOR' {
                $context = [pscustomobject]@{
                    Plan = [pscustomobject]@{
                        LifecycleEvent = 'Joiner'
                    }
                }

                $condition = @{
                    None = @(
                        @{ Equals = @{ Path = 'Plan.LifecycleEvent'; Value = 'Leaver' } }
                        @{ Equals = @{ Path = 'Plan.LifecycleEvent'; Value = 'Mover' } }
                    )
                }

                (Test-IdleCondition -Condition $condition -Context $context) | Should -BeTrue
            }

            It 'throws when schema validation fails' {
                $context = [pscustomobject]@{
                    Plan = [pscustomobject]@{
                        LifecycleEvent = 'Joiner'
                    }
                }

                # Invalid because Equals is missing Path
                $condition = @{
                    Equals = @{
                        Value = 'Joiner'
                    }
                }

                { Test-IdleCondition -Condition $condition -Context $context } | Should -Throw
            }
        }
    }
}

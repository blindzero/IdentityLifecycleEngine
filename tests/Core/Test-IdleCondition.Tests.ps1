Set-StrictMode -Version Latest

BeforeDiscovery {
    . (Join-Path (Split-Path -Path $PSScriptRoot -Parent) '_testHelpers.ps1')
    Import-IdleTestModule
}

Describe 'Condition DSL (schema + evaluator)' {

    InModuleScope 'IdLE.Core' {

        BeforeAll {
            # Guarding to ensure the functions are available.
            Get-Command Test-IdleConditionSchema -ErrorAction Stop | Out-Null
            Get-Command Test-IdleCondition -ErrorAction Stop | Out-Null
        }

        Context 'Schema validation' {

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

            It 'accepts Contains operator with Path + Value' {
                $condition = @{
                    Contains = @{
                        Path  = 'Request.Context.Identity.Entitlements'
                        Value = 'CN=Group,OU=Groups,DC=example,DC=com'
                    }
                }

                $errors = Test-IdleConditionSchema -Condition $condition -StepName 'Demo'
                $errors.Count | Should -Be 0
            }

            It 'rejects Contains with missing Path' {
                $condition = @{
                    Contains = @{
                        Value = 'Test'
                    }
                }

                $errors = Test-IdleConditionSchema -Condition $condition -StepName 'Demo'
                $errors.Count | Should -BeGreaterThan 0
            }

            It 'rejects Contains with missing Value' {
                $condition = @{
                    Contains = @{
                        Path = 'Request.Context.Identity.Entitlements'
                    }
                }

                $errors = Test-IdleConditionSchema -Condition $condition -StepName 'Demo'
                $errors.Count | Should -BeGreaterThan 0
            }

            It 'accepts NotContains operator with Path + Value' {
                $condition = @{
                    NotContains = @{
                        Path  = 'Request.Context.Identity.Entitlements'
                        Value = 'CN=Group,OU=Groups,DC=example,DC=com'
                    }
                }

                $errors = Test-IdleConditionSchema -Condition $condition -StepName 'Demo'
                $errors.Count | Should -Be 0
            }

            It 'accepts Like operator with Path + Pattern' {
                $condition = @{
                    Like = @{
                        Path    = 'Request.Context.Identity.Profile.DisplayName'
                        Pattern = '* (Contractor)'
                    }
                }

                $errors = Test-IdleConditionSchema -Condition $condition -StepName 'Demo'
                $errors.Count | Should -Be 0
            }

            It 'rejects Like with missing Pattern' {
                $condition = @{
                    Like = @{
                        Path = 'Request.Context.Identity.Profile.DisplayName'
                    }
                }

                $errors = Test-IdleConditionSchema -Condition $condition -StepName 'Demo'
                $errors.Count | Should -BeGreaterThan 0
            }

            It 'accepts NotLike operator with Path + Pattern' {
                $condition = @{
                    NotLike = @{
                        Path    = 'Request.Context.Identity.Entitlements'
                        Pattern = 'CN=HR-*'
                    }
                }

                $errors = Test-IdleConditionSchema -Condition $condition -StepName 'Demo'
                $errors.Count | Should -Be 0
            }
        }

        Context 'Evaluation' {

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

            It 'returns true when Contains finds value in list' {
                $context = [pscustomobject]@{
                    Request = [pscustomobject]@{
                        Context = [pscustomobject]@{
                            Views = [pscustomobject]@{
                                Identity = [pscustomobject]@{
                                    Entitlements = @(
                                        [pscustomobject]@{ Kind = 'Group'; Id = 'CN=Users,OU=Groups,DC=example,DC=com' }
                                        [pscustomobject]@{ Kind = 'Group'; Id = 'CN=BreakGlass-Users,OU=Groups,DC=example,DC=com' }
                                        [pscustomobject]@{ Kind = 'Group'; Id = 'CN=Admins,OU=Groups,DC=example,DC=com' }
                                    )
                                }
                            }
                        }
                    }
                }

                $condition = @{
                    Contains = @{
                        Path  = 'Request.Context.Views.Identity.Entitlements.Id'
                        Value = 'CN=BreakGlass-Users,OU=Groups,DC=example,DC=com'
                    }
                }

                (Test-IdleCondition -Condition $condition -Context $context) | Should -BeTrue
            }

            It 'returns false when Contains does not find value in list' {
                $context = [pscustomobject]@{
                    Request = [pscustomobject]@{
                        Context = [pscustomobject]@{
                            Views = [pscustomobject]@{
                                Identity = [pscustomobject]@{
                                    Entitlements = @(
                                        [pscustomobject]@{ Kind = 'Group'; Id = 'CN=Users,OU=Groups,DC=example,DC=com' }
                                        [pscustomobject]@{ Kind = 'Group'; Id = 'CN=Admins,OU=Groups,DC=example,DC=com' }
                                    )
                                }
                            }
                        }
                    }
                }

                $condition = @{
                    Contains = @{
                        Path  = 'Request.Context.Views.Identity.Entitlements.Id'
                        Value = 'CN=BreakGlass-Users,OU=Groups,DC=example,DC=com'
                    }
                }

                (Test-IdleCondition -Condition $condition -Context $context) | Should -BeFalse
            }

            It 'throws when Contains is used on scalar value' {
                $context = [pscustomobject]@{
                    Request = [pscustomobject]@{
                        Context = [pscustomobject]@{
                            Identity = [pscustomobject]@{
                                Name = 'John Doe'
                            }
                        }
                    }
                }

                $condition = @{
                    Contains = @{
                        Path  = 'Request.Context.Identity.Name'
                        Value = 'John'
                    }
                }

                { Test-IdleCondition -Condition $condition -Context $context } | Should -Throw
            }

            It 'throws when Contains is used on hashtable' {
                $context = [pscustomobject]@{
                    Request = [pscustomobject]@{
                        Context = [pscustomobject]@{
                            Identity = [pscustomobject]@{
                                Metadata = @{
                                    Department = 'Engineering'
                                    Location   = 'Seattle'
                                }
                            }
                        }
                    }
                }

                $condition = @{
                    Contains = @{
                        Path  = 'Request.Context.Identity.Metadata'
                        Value = 'Engineering'
                    }
                }

                { Test-IdleCondition -Condition $condition -Context $context } | Should -Throw -ExpectedMessage '*hashtable/dictionary*'
            }

            It 'throws when NotContains is used on hashtable' {
                $context = [pscustomobject]@{
                    Request = [pscustomobject]@{
                        Context = [pscustomobject]@{
                            Identity = [pscustomobject]@{
                                Metadata = @{
                                    Department = 'Engineering'
                                    Location   = 'Seattle'
                                }
                            }
                        }
                    }
                }

                $condition = @{
                    NotContains = @{
                        Path  = 'Request.Context.Identity.Metadata'
                        Value = 'HR'
                    }
                }

                { Test-IdleCondition -Condition $condition -Context $context } | Should -Throw -ExpectedMessage '*hashtable/dictionary*'
            }

            It 'throws when Like is used on hashtable' {
                $context = [pscustomobject]@{
                    Request = [pscustomobject]@{
                        Context = [pscustomobject]@{
                            Identity = [pscustomobject]@{
                                Metadata = @{
                                    Department = 'Engineering'
                                    Location   = 'Seattle'
                                }
                            }
                        }
                    }
                }

                $condition = @{
                    Like = @{
                        Path    = 'Request.Context.Identity.Metadata'
                        Pattern = 'Eng*'
                    }
                }

                { Test-IdleCondition -Condition $condition -Context $context } | Should -Throw -ExpectedMessage '*hashtable/dictionary*'
            }

            It 'throws when NotLike is used on hashtable' {
                $context = [pscustomobject]@{
                    Request = [pscustomobject]@{
                        Context = [pscustomobject]@{
                            Identity = [pscustomobject]@{
                                Metadata = @{
                                    Department = 'Engineering'
                                    Location   = 'Seattle'
                                }
                            }
                        }
                    }
                }

                $condition = @{
                    NotLike = @{
                        Path    = 'Request.Context.Identity.Metadata'
                        Pattern = 'HR*'
                    }
                }

                { Test-IdleCondition -Condition $condition -Context $context } | Should -Throw -ExpectedMessage '*hashtable/dictionary*'
            }

            It 'returns true when NotContains does not find value in list' {
                $context = [pscustomobject]@{
                    Request = [pscustomobject]@{
                        Context = [pscustomobject]@{
                            Views = [pscustomobject]@{
                                Identity = [pscustomobject]@{
                                    Entitlements = @(
                                        [pscustomobject]@{ Kind = 'Group'; Id = 'CN=Users,OU=Groups,DC=example,DC=com' }
                                        [pscustomobject]@{ Kind = 'Group'; Id = 'CN=Admins,OU=Groups,DC=example,DC=com' }
                                    )
                                }
                            }
                        }
                    }
                }

                $condition = @{
                    NotContains = @{
                        Path  = 'Request.Context.Views.Identity.Entitlements.Id'
                        Value = 'CN=BreakGlass-Users,OU=Groups,DC=example,DC=com'
                    }
                }

                (Test-IdleCondition -Condition $condition -Context $context) | Should -BeTrue
            }

            It 'returns false when NotContains finds value in list' {
                $context = [pscustomobject]@{
                    Request = [pscustomobject]@{
                        Context = [pscustomobject]@{
                            Views = [pscustomobject]@{
                                Identity = [pscustomobject]@{
                                    Entitlements = @(
                                        [pscustomobject]@{ Kind = 'Group'; Id = 'CN=Users,OU=Groups,DC=example,DC=com' }
                                        [pscustomobject]@{ Kind = 'Group'; Id = 'CN=BreakGlass-Users,OU=Groups,DC=example,DC=com' }
                                    )
                                }
                            }
                        }
                    }
                }

                $condition = @{
                    NotContains = @{
                        Path  = 'Request.Context.Views.Identity.Entitlements.Id'
                        Value = 'CN=BreakGlass-Users,OU=Groups,DC=example,DC=com'
                    }
                }

                (Test-IdleCondition -Condition $condition -Context $context) | Should -BeFalse
            }

            It 'returns true when Like matches scalar value' {
                $context = [pscustomobject]@{
                    Request = [pscustomobject]@{
                        Context = [pscustomobject]@{
                            Views = [pscustomobject]@{
                                Identity = [pscustomobject]@{
                                    Profile = [pscustomobject]@{
                                        Attributes = @{ DisplayName = 'John Doe (Contractor)' }
                                    }
                                }
                            }
                        }
                    }
                }

                $condition = @{
                    Like = @{
                        Path    = 'Request.Context.Views.Identity.Profile.Attributes.DisplayName'
                        Pattern = '* (Contractor)'
                    }
                }

                (Test-IdleCondition -Condition $condition -Context $context) | Should -BeTrue
            }

            It 'returns false when Like does not match scalar value' {
                $context = [pscustomobject]@{
                    Request = [pscustomobject]@{
                        Context = [pscustomobject]@{
                            Views = [pscustomobject]@{
                                Identity = [pscustomobject]@{
                                    Profile = [pscustomobject]@{
                                        Attributes = @{ DisplayName = 'John Doe' }
                                    }
                                }
                            }
                        }
                    }
                }

                $condition = @{
                    Like = @{
                        Path    = 'Request.Context.Views.Identity.Profile.Attributes.DisplayName'
                        Pattern = '* (Contractor)'
                    }
                }

                (Test-IdleCondition -Condition $condition -Context $context) | Should -BeFalse
            }

            It 'returns true when Like matches any element in list' {
                $context = [pscustomobject]@{
                    Request = [pscustomobject]@{
                        Context = [pscustomobject]@{
                            Views = [pscustomobject]@{
                                Identity = [pscustomobject]@{
                                    Entitlements = @(
                                        [pscustomobject]@{ Kind = 'Group'; Id = 'CN=Users,OU=Groups,DC=example,DC=com' }
                                        [pscustomobject]@{ Kind = 'Group'; Id = 'CN=HR-Employees,OU=Groups,DC=example,DC=com' }
                                        [pscustomobject]@{ Kind = 'Group'; Id = 'CN=Admins,OU=Groups,DC=example,DC=com' }
                                    )
                                }
                            }
                        }
                    }
                }

                $condition = @{
                    Like = @{
                        Path    = 'Request.Context.Views.Identity.Entitlements.Id'
                        Pattern = 'CN=HR-*'
                    }
                }

                (Test-IdleCondition -Condition $condition -Context $context) | Should -BeTrue
            }

            It 'returns false when Like does not match any element in list' {
                $context = [pscustomobject]@{
                    Request = [pscustomobject]@{
                        Context = [pscustomobject]@{
                            Views = [pscustomobject]@{
                                Identity = [pscustomobject]@{
                                    Entitlements = @(
                                        [pscustomobject]@{ Kind = 'Group'; Id = 'CN=Users,OU=Groups,DC=example,DC=com' }
                                        [pscustomobject]@{ Kind = 'Group'; Id = 'CN=Admins,OU=Groups,DC=example,DC=com' }
                                    )
                                }
                            }
                        }
                    }
                }

                $condition = @{
                    Like = @{
                        Path    = 'Request.Context.Views.Identity.Entitlements.Id'
                        Pattern = 'CN=HR-*'
                    }
                }

                (Test-IdleCondition -Condition $condition -Context $context) | Should -BeFalse
            }

            It 'returns true when NotLike does not match scalar value' {
                $context = [pscustomobject]@{
                    Request = [pscustomobject]@{
                        Context = [pscustomobject]@{
                            Views = [pscustomobject]@{
                                Identity = [pscustomobject]@{
                                    Profile = [pscustomobject]@{
                                        Attributes = @{ DisplayName = 'John Doe' }
                                    }
                                }
                            }
                        }
                    }
                }

                $condition = @{
                    NotLike = @{
                        Path    = 'Request.Context.Views.Identity.Profile.Attributes.DisplayName'
                        Pattern = '* (Contractor)'
                    }
                }

                (Test-IdleCondition -Condition $condition -Context $context) | Should -BeTrue
            }

            It 'returns false when NotLike matches scalar value' {
                $context = [pscustomobject]@{
                    Request = [pscustomobject]@{
                        Context = [pscustomobject]@{
                            Views = [pscustomobject]@{
                                Identity = [pscustomobject]@{
                                    Profile = [pscustomobject]@{
                                        Attributes = @{ DisplayName = 'John Doe (Contractor)' }
                                    }
                                }
                            }
                        }
                    }
                }

                $condition = @{
                    NotLike = @{
                        Path    = 'Request.Context.Views.Identity.Profile.Attributes.DisplayName'
                        Pattern = '* (Contractor)'
                    }
                }

                (Test-IdleCondition -Condition $condition -Context $context) | Should -BeFalse
            }

            It 'returns true when NotLike does not match any element in list' {
                $context = [pscustomobject]@{
                    Request = [pscustomobject]@{
                        Context = [pscustomobject]@{
                            Views = [pscustomobject]@{
                                Identity = [pscustomobject]@{
                                    Entitlements = @(
                                        [pscustomobject]@{ Kind = 'Group'; Id = 'CN=Users,OU=Groups,DC=example,DC=com' }
                                        [pscustomobject]@{ Kind = 'Group'; Id = 'CN=Admins,OU=Groups,DC=example,DC=com' }
                                    )
                                }
                            }
                        }
                    }
                }

                $condition = @{
                    NotLike = @{
                        Path    = 'Request.Context.Views.Identity.Entitlements.Id'
                        Pattern = 'CN=HR-*'
                    }
                }

                (Test-IdleCondition -Condition $condition -Context $context) | Should -BeTrue
            }

            It 'returns false when NotLike matches any element in list' {
                $context = [pscustomobject]@{
                    Request = [pscustomobject]@{
                        Context = [pscustomobject]@{
                            Views = [pscustomobject]@{
                                Identity = [pscustomobject]@{
                                    Entitlements = @(
                                        [pscustomobject]@{ Kind = 'Group'; Id = 'CN=Users,OU=Groups,DC=example,DC=com' }
                                        [pscustomobject]@{ Kind = 'Group'; Id = 'CN=HR-Employees,OU=Groups,DC=example,DC=com' }
                                    )
                                }
                            }
                        }
                    }
                }

                $condition = @{
                    NotLike = @{
                        Path    = 'Request.Context.Views.Identity.Entitlements.Id'
                        Pattern = 'CN=HR-*'
                    }
                }

                (Test-IdleCondition -Condition $condition -Context $context) | Should -BeFalse
            }

            It 'Contains is case-insensitive' {
                $context = [pscustomobject]@{
                    Request = [pscustomobject]@{
                        Context = [pscustomobject]@{
                            Views = [pscustomobject]@{
                                Identity = [pscustomobject]@{
                                    Entitlements = @(
                                        [pscustomobject]@{ Kind = 'Group'; Id = 'CN=admins,OU=Groups,DC=example,DC=com' }
                                        [pscustomobject]@{ Kind = 'Group'; Id = 'CN=users,OU=Groups,DC=example,DC=com' }
                                    )
                                }
                            }
                        }
                    }
                }

                $condition = @{
                    Contains = @{
                        Path  = 'Request.Context.Views.Identity.Entitlements.Id'
                        Value = 'CN=USERS,OU=Groups,DC=example,DC=com'
                    }
                }

                (Test-IdleCondition -Condition $condition -Context $context) | Should -BeTrue
            }

            It 'Like is case-insensitive' {
                $context = [pscustomobject]@{
                    Request = [pscustomobject]@{
                        Context = [pscustomobject]@{
                            Views = [pscustomobject]@{
                                Identity = [pscustomobject]@{
                                    Profile = [pscustomobject]@{
                                        Attributes = @{ DisplayName = 'john doe (contractor)' }
                                    }
                                }
                            }
                        }
                    }
                }

                $condition = @{
                    Like = @{
                        Path    = 'Request.Context.Views.Identity.Profile.Attributes.DisplayName'
                        Pattern = '* (CONTRACTOR)'
                    }
                }

                (Test-IdleCondition -Condition $condition -Context $context) | Should -BeTrue
            }
        }
    }
}

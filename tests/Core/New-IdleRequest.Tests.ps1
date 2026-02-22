Set-StrictMode -Version Latest

BeforeAll {
    . (Join-Path (Split-Path -Path $PSScriptRoot -Parent) '_testHelpers.ps1')
    Import-IdleTestModule
}

Describe 'New-IdleRequest' {
    Context 'Creation and defaults' {
        It 'creates a request object with the expected type' {
            $req = New-IdleRequest -LifecycleEvent 'Joiner'
            $req | Should -Not -BeNullOrEmpty
            $req.GetType().Name | Should -Be 'IdleLifecycleRequest'
        }

        It 'generates CorrelationId when missing' {
            $req = New-IdleRequest -LifecycleEvent 'Joiner'
            $req.CorrelationId | Should -Not -BeNullOrEmpty
            { [guid]::Parse($req.CorrelationId) } | Should -Not -Throw
        }

        It 'preserves CorrelationId when provided' {
            $cid = ([guid]::NewGuid()).Guid
            $req = New-IdleRequest -LifecycleEvent 'Joiner' -CorrelationId $cid
            $req.CorrelationId | Should -Be $cid
        }

        It 'defaults IdentityKeys and DesiredState to empty hashtables when omitted' {
            $req = New-IdleRequest -LifecycleEvent 'Joiner'
            $req.IdentityKeys | Should -BeOfType 'hashtable'
            $req.DesiredState | Should -BeOfType 'hashtable'
            $req.IdentityKeys.Count | Should -Be 0
            $req.DesiredState.Count | Should -Be 0
        }

        It 'defaults Intent and Context to empty hashtables when omitted' {
            $req = New-IdleRequest -LifecycleEvent 'Joiner'
            $req.Intent  | Should -BeOfType 'hashtable'
            $req.Context | Should -BeOfType 'hashtable'
            $req.Intent.Count  | Should -Be 0
            $req.Context.Count | Should -Be 0
        }
    }

    Context 'Optional properties' {
        It 'leaves Changes as null when omitted' {
            $req = New-IdleRequest -LifecycleEvent 'Mover'
            $req.Changes | Should -BeNullOrEmpty
        }

        It 'accepts Changes when provided' {
            $req = New-IdleRequest -LifecycleEvent 'Mover' -Changes @{
                Attributes = @{
                    Department = @{
                        From = 'Sales'
                        To   = 'IT'
                    }
                }
            }

            $req.Changes | Should -BeOfType 'hashtable'
            $req.Changes.Attributes.Department.From | Should -Be 'Sales'
            $req.Changes.Attributes.Department.To   | Should -Be 'IT'
        }

        It 'treats Actor as optional (null when omitted)' {
            $req = New-IdleRequest -LifecycleEvent 'Joiner'
            $req.Actor | Should -BeNullOrEmpty
        }

        It 'accepts Actor when provided' {
            $req = New-IdleRequest -LifecycleEvent 'Joiner' -Actor 'alice@contoso.com'
            $req.Actor | Should -Be 'alice@contoso.com'
        }
    }

    Context 'Intent parameter' {
        It 'accepts -Intent and populates Intent property' {
            $req = New-IdleRequest -LifecycleEvent 'Joiner' -Intent @{ Department = 'Engineering' }
            $req.Intent | Should -BeOfType 'hashtable'
            $req.Intent.Department | Should -Be 'Engineering'
        }

        It 'mirrors Intent value into DesiredState for backward compatibility' {
            $req = New-IdleRequest -LifecycleEvent 'Joiner' -Intent @{ Title = 'Engineer' }
            $req.DesiredState.Title | Should -Be 'Engineer'
        }
    }

    Context 'Context parameter' {
        It 'accepts -Context and populates Context property' {
            $req = New-IdleRequest -LifecycleEvent 'Joiner' -Context @{ Identity = @{ ObjectId = 'abc-123' } }
            $req.Context | Should -BeOfType 'hashtable'
            $req.Context.Identity.ObjectId | Should -Be 'abc-123'
        }
    }

    Context 'DesiredState transition window' {
        It 'maps DesiredState to Intent when only DesiredState is provided' {
            $req = New-IdleRequest -LifecycleEvent 'Joiner' -DesiredState @{ Department = 'HR' } 3>$null
            $req.Intent.Department | Should -Be 'HR'
        }

        It 'emits a deprecation warning when DesiredState is used' {
            $warningMessage = $null
            New-IdleRequest -LifecycleEvent 'Joiner' -DesiredState @{ Foo = 'Bar' } -WarningVariable warningMessage 3>$null | Out-Null
            $warningMessage | Should -Not -BeNullOrEmpty
            $warningMessage | Should -Match 'deprecated'
            $warningMessage | Should -Match 'Intent'
        }

        It 'rejects providing both DesiredState and Intent' {
            { New-IdleRequest -LifecycleEvent 'Joiner' -DesiredState @{ A = '1' } -Intent @{ B = '2' } } |
                Should -Throw -ExpectedMessage "*'DesiredState' is deprecated*"
        }
    }
}

Describe 'New-IdleRequest - data-only validation' {
    Context 'ScriptBlock rejection' {
        It 'rejects ScriptBlock in DesiredState when provided' {
            try {
                New-IdleRequest -LifecycleEvent 'Joiner' -DesiredState @{
                    Attributes = @{ Department = { 'IT' } }
                }
                throw 'Expected an exception but none was thrown.'
            }
            catch {
                $_.Exception | Should -BeOfType ([System.ArgumentException])
                $_.Exception.Message | Should -Match 'ScriptBlocks are not allowed'
                $_.Exception.Message | Should -Match 'Intent'
            }
        }

        It 'rejects ScriptBlock nested in arrays' {
            try {
                New-IdleRequest -LifecycleEvent 'Joiner' -DesiredState @{
                    Entitlements = @(
                        @{ Type = 'Group'; Value = 'APP-CRM-Users' }
                        @{ Type = 'Custom'; Value = { 'NOPE' } }
                    )
                }
            }
            catch {
                $_.Exception | Should -BeOfType ([System.ArgumentException])
                $_.Exception.Message | Should -Match 'ScriptBlocks are not allowed'
                $_.Exception.Message | Should -Match 'Intent'
            }
        }

        It 'rejects ScriptBlock in Intent when provided' {
            {
                New-IdleRequest -LifecycleEvent 'Joiner' -Intent @{
                    Attributes = @{ Department = { 'IT' } }
                }
            } | Should -Throw -ExpectedMessage '*ScriptBlocks are not allowed*'
        }

        It 'rejects ScriptBlock in Context when provided' {
            {
                New-IdleRequest -LifecycleEvent 'Joiner' -Context @{
                    Identity = @{ Value = { 'NOPE' } }
                }
            } | Should -Throw -ExpectedMessage '*ScriptBlocks are not allowed*'
        }

        It 'rejects ScriptBlock in Changes when provided' {
            try {
                New-IdleRequest -LifecycleEvent 'Joiner' -Changes @{
                    Attributes = @{
                        Department = @{
                            From = 'Sales'
                            To   = { 'IT' }
                        }
                    }
                }
                throw 'Expected an exception but none was thrown.'
            }
            catch {
                $_.Exception | Should -BeOfType ([System.ArgumentException])
                $_.Exception.Message | Should -Match 'ScriptBlocks are not allowed'
                $_.Exception.Message | Should -Match 'Changes'
            }
        }
    }
}

Describe 'New-IdlePlan - Request.Identity rejection' {
    BeforeAll {
        function global:Invoke-IdleTestNoopStep {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory)][ValidateNotNull()][object] $Context,
                [Parameter(Mandatory)][ValidateNotNull()][object] $Step
            )
            return [pscustomobject]@{
                PSTypeName = 'IdLE.StepResult'
                Name       = [string]$Step.Name
                Type       = [string]$Step.Type
                Status     = 'Completed'
                Error      = $null
            }
        }
    }

    AfterAll {
        Remove-Item -Path 'Function:\Invoke-IdleTestNoopStep' -ErrorAction SilentlyContinue
    }

    It 'rejects a request object that contains an Identity property' {
        $badRequest = [pscustomobject]@{
            PSTypeName     = 'IdLE.LifecycleRequest'
            LifecycleEvent = 'Joiner'
            CorrelationId  = [guid]::NewGuid().ToString()
            Identity       = @{ ObjectId = 'abc-123' }
        }

        $wfPath = Join-Path $PSScriptRoot '..' 'fixtures/workflows/template-tests/template-simple.psd1'
        $providers = @{
            StepRegistry = @{ 'IdLE.Step.Test' = 'Invoke-IdleTestNoopStep' }
            StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.Test')
        }

        { New-IdlePlan -WorkflowPath $wfPath -Request $badRequest -Providers $providers } |
            Should -Throw -ExpectedMessage "*must not contain property 'Identity'*"
    }
}


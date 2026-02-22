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

        It 'defaults IdentityKeys to an empty hashtable when omitted' {
            $req = New-IdleRequest -LifecycleEvent 'Joiner'
            $req.IdentityKeys | Should -BeOfType 'hashtable'
            $req.IdentityKeys.Count | Should -Be 0
        }

        It 'defaults Intent and Context to empty hashtables when omitted' {
            $req = New-IdleRequest -LifecycleEvent 'Joiner'
            $req.Intent  | Should -BeOfType 'hashtable'
            $req.Context | Should -BeOfType 'hashtable'
            $req.Intent.Count  | Should -Be 0
            $req.Context.Count | Should -Be 0
        }

        It 'does not expose a DesiredState property' {
            $req = New-IdleRequest -LifecycleEvent 'Joiner'
            $req.PSObject.Properties.Name | Should -Not -Contain 'DesiredState'
        }
    }

    Context 'Optional properties' {
        It 'treats Actor as optional (null when omitted)' {
            $req = New-IdleRequest -LifecycleEvent 'Joiner'
            $req.Actor | Should -BeNullOrEmpty
        }

        It 'accepts Actor when provided' {
            $req = New-IdleRequest -LifecycleEvent 'Joiner' -Actor 'alice@contoso.com'
            $req.Actor | Should -Be 'alice@contoso.com'
        }

        It 'does not expose a Changes property' {
            $req = New-IdleRequest -LifecycleEvent 'Joiner'
            $req.PSObject.Properties.Name | Should -Not -Contain 'Changes'
        }

        It 'does not accept a -Changes parameter' {
            { New-IdleRequest -LifecycleEvent 'Joiner' -Changes @{ Foo = 'Bar' } } |
                Should -Throw
        }
    }

    Context 'Intent parameter' {
        It 'accepts -Intent and populates Intent property' {
            $req = New-IdleRequest -LifecycleEvent 'Joiner' -Intent @{ Department = 'Engineering' }
            $req.Intent | Should -BeOfType 'hashtable'
            $req.Intent.Department | Should -Be 'Engineering'
        }
    }

    Context 'Context parameter' {
        It 'accepts -Context and populates Context property' {
            $req = New-IdleRequest -LifecycleEvent 'Joiner' -Context @{ Identity = @{ ObjectId = 'abc-123' } }
            $req.Context | Should -BeOfType 'hashtable'
            $req.Context.Identity.ObjectId | Should -Be 'abc-123'
        }
    }
}

Describe 'New-IdleRequest - data-only validation' {
    Context 'ScriptBlock rejection' {
        It 'rejects ScriptBlock in Intent when provided' {
            {
                New-IdleRequest -LifecycleEvent 'Joiner' -Intent @{
                    Attributes = @{ Department = { 'IT' } }
                }
            } | Should -Throw -ExpectedMessage '*ScriptBlocks are not allowed*'
        }

        It 'rejects ScriptBlock nested in arrays' {
            {
                New-IdleRequest -LifecycleEvent 'Joiner' -Intent @{
                    Entitlements = @(
                        @{ Type = 'Group'; Value = 'APP-CRM-Users' }
                        @{ Type = 'Custom'; Value = { 'NOPE' } }
                    )
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
    }
}

Describe 'New-IdlePlan - Request.Changes rejection' {
    BeforeAll {
        function global:Invoke-IdleTestNoopStep2 {
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
        Remove-Item -Path 'Function:\Invoke-IdleTestNoopStep2' -ErrorAction SilentlyContinue
    }

    It 'rejects a request object that contains a Changes property' {
        $badRequest = [pscustomobject]@{
            PSTypeName     = 'IdLE.LifecycleRequest'
            LifecycleEvent = 'Joiner'
            CorrelationId  = [guid]::NewGuid().ToString()
            Changes        = @{ Department = @{ From = 'Sales'; To = 'IT' } }
        }

        $wfPath = Join-Path $PSScriptRoot '..' 'fixtures/workflows/template-tests/template-simple.psd1'
        $providers = @{
            StepRegistry = @{ 'IdLE.Step.Test' = 'Invoke-IdleTestNoopStep2' }
            StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.Test')
        }

        { New-IdlePlan -WorkflowPath $wfPath -Request $badRequest -Providers $providers } |
            Should -Throw -ExpectedMessage "*must not contain property 'Changes'*"
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

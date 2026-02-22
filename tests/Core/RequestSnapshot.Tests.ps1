Set-StrictMode -Version Latest

BeforeDiscovery {
    . (Join-Path (Split-Path -Path $PSScriptRoot -Parent) '_testHelpers.ps1')
    Import-IdleTestModule
}

Describe 'RequestSnapshot - plan export contract' {

    InModuleScope 'IdLE.Core' {

        # ---------------------------------------------------------------------------
        # Helper: build a minimal plan object shaped like the output of New-IdlePlanObject
        # ---------------------------------------------------------------------------
        BeforeAll {
            function New-TestPlan {
                param(
                    [hashtable] $Intent  = @{},
                    [hashtable] $Context = @{},
                    [hashtable] $IdentityKeys = @{ userId = 'jdoe' }
                )

                [pscustomobject]@{
                    PSTypeName = 'IdLE.Plan'
                    Request    = [pscustomobject]@{
                        PSTypeName     = 'IdLE.LifecycleRequestSnapshot'
                        LifecycleEvent = 'Joiner'
                        CorrelationId  = '11111111-1111-1111-1111-111111111111'
                        Actor          = $null
                        IdentityKeys   = $IdentityKeys
                        Intent         = $Intent
                        Context        = $Context
                    }
                    Steps          = @()
                    OnFailureSteps = @()
                }
            }
        }

        Context 'Intent and Context are included in request.input' {
            It 'exports Request.Intent into request.input.intent' {
                $plan = New-TestPlan -Intent @{ department = 'IT'; title = 'Engineer' }

                $json = Export-IdlePlanObject -Plan $plan | ConvertFrom-Json

                $json.request.input.intent | Should -Not -BeNullOrEmpty
                $json.request.input.intent.department | Should -Be 'IT'
                $json.request.input.intent.title      | Should -Be 'Engineer'
            }

            It 'exports Request.Context into request.input.context' {
                $plan = New-TestPlan -Context @{ Identity = @{ ObjectId = 'abc-123' } }

                $json = Export-IdlePlanObject -Plan $plan | ConvertFrom-Json

                $json.request.input.context | Should -Not -BeNullOrEmpty
                $json.request.input.context.Identity.ObjectId | Should -Be 'abc-123'
            }

            It 'exports an empty context as an empty object (not null)' {
                $plan = New-TestPlan -Context @{}

                $json = Export-IdlePlanObject -Plan $plan | ConvertFrom-Json

                $json.request.input.context | Should -Not -Be $null
            }

            It 'exports IdentityKeys alongside Intent and Context' {
                $plan = New-TestPlan `
                    -IdentityKeys @{ userId = 'jdoe'; employeeId = '42' } `
                    -Intent       @{ department = 'IT' } `
                    -Context      @{ source = 'HR' }

                $json = Export-IdlePlanObject -Plan $plan | ConvertFrom-Json

                $json.request.input.identityKeys.userId     | Should -Be 'jdoe'
                $json.request.input.identityKeys.employeeId | Should -Be '42'
                $json.request.input.intent.department       | Should -Be 'IT'
                $json.request.input.context.source          | Should -Be 'HR'
            }
        }

        Context 'ScriptBlock safety' {
            It 'redacts a ScriptBlock value inside Intent at the export boundary' {
                # ScriptBlocks are rejected at request-creation time via Assert-IdleNoScriptBlock.
                # Here we verify the export boundary independently also redacts them,
                # guarding against any path that bypasses request-creation validation.
                $plan = [pscustomobject]@{
                    PSTypeName = 'IdLE.Plan'
                    Request    = [pscustomobject]@{
                        PSTypeName    = 'IdLE.LifecycleRequestSnapshot'
                        LifecycleEvent = 'Joiner'
                        CorrelationId  = 'corr-sb-01'
                        Actor          = $null
                        IdentityKeys   = @{ userId = 'test' }
                        Intent         = @{ action = { Write-Output 'bad' } }
                        Context        = @{}
                    }
                    Steps          = @()
                    OnFailureSteps = @()
                }

                $json = Export-IdlePlanObject -Plan $plan

                $json | Should -Not -Match 'bad'
                $json | Should -Match '\[REDACTED\]'
            }

            It 'does not emit ScriptBlock text in the exported JSON for Context' {
                $plan = [pscustomobject]@{
                    PSTypeName = 'IdLE.Plan'
                    Request    = [pscustomobject]@{
                        PSTypeName     = 'IdLE.LifecycleRequestSnapshot'
                        LifecycleEvent = 'Joiner'
                        CorrelationId  = 'corr-sb-02'
                        Actor          = $null
                        IdentityKeys   = @{ userId = 'test' }
                        Intent         = @{}
                        Context        = @{ compute = { 1 + 1 } }
                    }
                    Steps          = @()
                    OnFailureSteps = @()
                }

                $json = Export-IdlePlanObject -Plan $plan

                $json | Should -Not -Match '1 \+ 1'
                $json | Should -Match '\[REDACTED\]'
            }
        }

        Context 'Size limits' {
            It 'truncates an oversized Intent field with a deterministic marker' {
                # Build an Intent whose serialized JSON exceeds 64 KB (65536 bytes).
                $largeString = 'x' * 70000
                $plan = New-TestPlan -Intent @{ bigField = $largeString }

                $json = Export-IdlePlanObject -Plan $plan | ConvertFrom-Json

                $json.request.input.intent | Should -BeLike '*TRUNCATED*bytes*'
            }

            It 'truncates an oversized Context field with a deterministic marker' {
                $largeString = 'x' * 70000
                $plan = New-TestPlan -Context @{ bigField = $largeString }

                $json = Export-IdlePlanObject -Plan $plan | ConvertFrom-Json

                $json.request.input.context | Should -BeLike '*TRUNCATED*bytes*'
            }

            It 'does not truncate Intent that is within the 64 KB limit' {
                $plan = New-TestPlan -Intent @{ department = 'IT' }

                $json = Export-IdlePlanObject -Plan $plan | ConvertFrom-Json

                $json.request.input.intent | Should -Not -BeLike '*TRUNCATED*'
                $json.request.input.intent.department | Should -Be 'IT'
            }

            It 'truncation marker includes the original byte count' {
                $largeString = 'x' * 70000
                $plan = New-TestPlan -Intent @{ bigField = $largeString }

                $json = Export-IdlePlanObject -Plan $plan | ConvertFrom-Json

                $marker = $json.request.input.intent
                $marker | Should -Match '^\[TRUNCATED - \d+ bytes\]$'
            }
        }
    }
}

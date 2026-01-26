Set-StrictMode -Version Latest

BeforeAll {
    . (Join-Path (Split-Path -Path $PSScriptRoot -Parent) '_testHelpers.ps1')
    Import-IdleTestModule
}

Describe 'Invoke-IdleStepEnsureEntitlement (built-in step)' {
    BeforeEach {
        $script:Provider = New-IdleMockIdentityProvider
        $script:Context = [pscustomobject]@{
            PSTypeName = 'IdLE.ExecutionContext'
            Plan       = $null
            Providers  = @{ Identity = $script:Provider }
            EventSink  = [pscustomobject]@{ WriteEvent = { param($Type, $Message, $StepName, $Data) } }
        }

        $script:StepTemplate = [pscustomobject]@{
            Name = 'Ensure entitlement'
            Type = 'IdLE.Step.EnsureEntitlement'
            With = @{
                IdentityKey = 'user1'
                Entitlement = @{ Kind = 'Group'; Id = 'demo-group'; DisplayName = 'Demo Group' }
                State       = 'Present'
                Provider    = 'Identity'
            }
        }
    }

    It 'grants entitlement when missing' {
        $null = $script:Provider.EnsureAttribute('user1', 'Seed', 'Value')

        $step = $script:StepTemplate
        $handler = 'IdLE.Steps.Common\Invoke-IdleStepEnsureEntitlement'

        $result = & $handler -Context $script:Context -Step $step

        $result.Status | Should -Be 'Completed'
        $result.Changed | Should -BeTrue

        $assignments = $script:Provider.ListEntitlements('user1')
        $assignments | Where-Object { $_.Kind -eq 'Group' -and $_.Id -eq 'demo-group' } | Should -Not -BeNullOrEmpty
    }

    It 'skips grant when entitlement already present (case-insensitive id match)' {
        $null = $script:Provider.EnsureAttribute('user1', 'Seed', 'Value')
        $null = $script:Provider.GrantEntitlement('user1', @{ Kind = 'Group'; Id = 'DEMO-GROUP' })

        $handler = 'IdLE.Steps.Common\Invoke-IdleStepEnsureEntitlement'
        $result = & $handler -Context $script:Context -Step $script:StepTemplate

        $result.Status | Should -Be 'Completed'
        $result.Changed | Should -BeFalse
    }

    It 'revokes entitlement when state is Absent' {
        $null = $script:Provider.EnsureAttribute('user1', 'Seed', 'Value')
        $null = $script:Provider.GrantEntitlement('user1', @{ Kind = 'Group'; Id = 'demo-group' })

        $step = $script:StepTemplate
        $step.With.State = 'Absent'

        $handler = 'IdLE.Steps.Common\Invoke-IdleStepEnsureEntitlement'
        $result = & $handler -Context $script:Context -Step $step

        $result.Status | Should -Be 'Completed'
        $result.Changed | Should -BeTrue

        $script:Provider.ListEntitlements('user1') | Should -BeNullOrEmpty
    }

    It 'throws when the provider is missing' {
        $script:Context.Providers.Clear()

        $handler = 'IdLE.Steps.Common\Invoke-IdleStepEnsureEntitlement'
        { & $handler -Context $script:Context -Step $script:StepTemplate } | Should -Throw -ErrorId *
    }

    It 'bubbles up provider errors when the identity is unknown' {
        $handler = 'IdLE.Steps.Common\Invoke-IdleStepEnsureEntitlement'
        { & $handler -Context $script:Context -Step $script:StepTemplate } | Should -Throw -ErrorId *
    }
}

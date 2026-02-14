Set-StrictMode -Version Latest

BeforeAll {
    . (Join-Path (Split-Path -Path $PSScriptRoot -Parent) '_testHelpers.ps1')
    Import-IdleTestModule

    function global:Invoke-IdleTestNoopStep {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [ValidateNotNull()]
            [object] $Context,

            [Parameter(Mandatory)]
            [ValidateNotNull()]
            [object] $Step
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

Describe 'New-IdlePlan' {
    Context 'Plan normalization' {
        It 'creates a plan with normalized steps' {
            $wfPath = New-IdleTestWorkflowFile -FileName 'joiner.psd1' -Content @'
@{
  Name           = 'Joiner - Standard'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{ Name = 'ResolveIdentity'; Type = 'IdLE.Step.ResolveIdentity' }
    @{ Name = 'EnsureAttributes'; Type = 'IdLE.Step.EnsureAttributes'; With = @{ Mode = 'Minimal' } }
  )
}
'@

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner'

            $dummyProvider = [pscustomobject]@{ PSTypeName = 'IdLE.Provider.TestDummy' }
            $dummyProvider | Add-Member -MemberType ScriptMethod -Name GetCapabilities -Value {
                return @('IdLE.Identity.Attribute.Ensure')
            }

            $providers = @{
                Dummy        = $true
                Identity     = $dummyProvider
                StepRegistry = @{
                    'IdLE.Step.ResolveIdentity'  = 'Invoke-IdleTestNoopStep'
                    'IdLE.Step.EnsureAttributes' = 'Invoke-IdleTestNoopStep'
                }
                StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.ResolveIdentity')
            }

            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

            $plan | Should -Not -BeNullOrEmpty
            $plan.PSTypeNames | Should -Contain 'IdLE.Plan'
            $plan.WorkflowName | Should -Be 'Joiner - Standard'
            $plan.LifecycleEvent | Should -Be 'Joiner'
            $plan.CorrelationId | Should -Be $req.CorrelationId

            @($plan.Steps).Count | Should -Be 2
            $plan.Steps[0].PSTypeNames | Should -Contain 'IdLE.PlanStep'
            $plan.Steps[0].Name | Should -Be 'ResolveIdentity'
            $plan.Steps[0].Type | Should -Be 'IdLE.Step.ResolveIdentity'

            @($plan.Actions).Count | Should -Be 0
            @($plan.Warnings).Count | Should -Be 0

            $plan.Providers.Dummy | Should -BeTrue

            $plan.PSObject.Properties.Name | Should -Contain 'OnFailureSteps'
            @($plan.OnFailureSteps).Count | Should -Be 0
        }
    }

    Context 'OnFailureSteps normalization' {
        It 'normalizes OnFailureSteps and evaluates their conditions during planning' {
            $wfPath = New-IdleTestWorkflowFile -FileName 'joiner-onfailure.psd1' -Content @'
@{
  Name           = 'Joiner - OnFailureSteps'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{ Name = 'ResolveIdentity'; Type = 'IdLE.Step.ResolveIdentity' }
  )
  OnFailureSteps = @(
    @{
      Name      = 'Containment'
      Type      = 'IdLE.Step.Containment'
      Condition = @{ Equals = @{ Path = 'Plan.LifecycleEvent'; Value = 'Joiner' } }
      With      = @{ Mode = 'Quarantine' }
    }
    @{
      Name      = 'NeverApplicable'
      Type      = 'IdLE.Step.NeverApplicable'
      Condition = @{ Equals = @{ Path = 'Plan.LifecycleEvent'; Value = 'Mover' } }
    }
  )
}
'@

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner'
            $providers = @{
                Dummy        = $true
                StepRegistry = @{
                    'IdLE.Step.ResolveIdentity' = 'Invoke-IdleTestNoopStep'
                    'IdLE.Step.Containment'     = 'Invoke-IdleTestNoopStep'
                    'IdLE.Step.NeverApplicable' = 'Invoke-IdleTestNoopStep'
                }
                StepMetadata = New-IdleTestStepMetadata -StepTypes @(
                    'IdLE.Step.ResolveIdentity',
                    'IdLE.Step.Containment',
                    'IdLE.Step.NeverApplicable'
                )
            }

            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

            $plan | Should -Not -BeNullOrEmpty
            $plan.PSObject.Properties.Name | Should -Contain 'OnFailureSteps'
            @($plan.OnFailureSteps).Count | Should -Be 2

            $plan.OnFailureSteps[0].PSTypeNames | Should -Contain 'IdLE.PlanStep'
            $plan.OnFailureSteps[0].Name | Should -Be 'Containment'
            $plan.OnFailureSteps[0].Type | Should -Be 'IdLE.Step.Containment'
            $plan.OnFailureSteps[0].Status | Should -Be 'Planned'
            $plan.OnFailureSteps[0].With.Mode | Should -Be 'Quarantine'

            $plan.OnFailureSteps[1].PSTypeNames | Should -Contain 'IdLE.PlanStep'
            $plan.OnFailureSteps[1].Name | Should -Be 'NeverApplicable'
            $plan.OnFailureSteps[1].Type | Should -Be 'IdLE.Step.NeverApplicable'
            $plan.OnFailureSteps[1].Status | Should -Be 'NotApplicable'
        }
    }

    Context 'Validation' {
        It 'throws when request LifecycleEvent does not match workflow LifecycleEvent' {
            $wfPath = New-IdleTestWorkflowFile -FileName 'joiner.psd1' -Content @'
@{
  Name           = 'Joiner - Standard'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{ Name = 'ResolveIdentity'; Type = 'IdLE.Step.ResolveIdentity' }
  )
}
'@

            $req = New-IdleTestRequest -LifecycleEvent 'Leaver'

            { New-IdlePlan -WorkflowPath $wfPath -Request $req } | Should -Throw -ExpectedMessage '*does not match request LifecycleEvent*'
        }
    }
}

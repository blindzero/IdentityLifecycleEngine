Set-StrictMode -Version Latest

BeforeAll {
    . (Join-Path (Split-Path -Path $PSScriptRoot -Parent) '_testHelpers.ps1')
    Import-IdleTestModule
    $script:FixturesPath = Join-Path $PSScriptRoot '..' 'fixtures/workflows'

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
            $wfPath = Join-Path $script:FixturesPath 'joiner-normalized.psd1'

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

        It 'associates precondition warnings with the correct step even when Steps and OnFailureSteps share a name' {
            $wfPath = New-IdleTestWorkflowFile -FileName 'joiner-shared-step-name-warning.psd1' -Content @'
@{
  Name           = 'Joiner - Shared Step Name Warning'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name         = 'SharedName'
      Type         = 'IdLE.Step.ResolveIdentity'
      Precondition = @{ Exists = 'Request.Context.MissingAtPlan' }
    }
  )
  OnFailureSteps = @(
    @{
      Name = 'SharedName'
      Type = 'IdLE.Step.Containment'
      With = @{ Mode = 'Quarantine' }
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
                }
                StepMetadata = New-IdleTestStepMetadata -StepTypes @(
                    'IdLE.Step.ResolveIdentity',
                    'IdLE.Step.Containment'
                )
            }

            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

            @($plan.Warnings).Count | Should -BeGreaterThan 0
            @($plan.Steps[0].Warnings).Count | Should -Be 1
            $plan.Steps[0].Warnings[0].Code | Should -Be 'PreconditionContextPathUnresolvedAtPlan'
            @($plan.OnFailureSteps[0].Warnings).Count | Should -Be 0
        }
    }

    Context 'Condition skips With processing' {
        It 'does not fail planning when condition is false and With references missing data (template resolution skipped)' {
            $wfPath = New-IdleTestWorkflowFile -FileName 'condition-skip-template.psd1' -Content @'
@{
  Name           = 'Condition Skip Template'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name      = 'ConditionalStep'
      Type      = 'IdLE.Step.ConditionalSkipTest'
      Condition = @{ Equals = @{ Path = 'Plan.LifecycleEvent'; Value = 'Leaver' } }
      With      = @{
        Value = '{{Request.Intent.MissingKey}}'
      }
    }
  )
}
'@

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner'
            $providers = @{
                StepRegistry = @{ 'IdLE.Step.ConditionalSkipTest' = 'Invoke-IdleTestNoopStep' }
                StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.ConditionalSkipTest')
            }

            # Must not throw despite template referencing absent Request.Intent.MissingKey
            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

            $plan | Should -Not -BeNullOrEmpty
            @($plan.Steps).Count | Should -Be 1
            $plan.Steps[0].Status | Should -Be 'NotApplicable'
        }

        It 'does not fail planning when condition is false and With is missing a required schema key' {
            $wfPath = New-IdleTestWorkflowFile -FileName 'condition-skip-schema.psd1' -Content @'
@{
  Name           = 'Condition Skip Schema'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name      = 'StrictStep'
      Type      = 'IdLE.Step.StrictSchemaTest'
      Condition = @{ Equals = @{ Path = 'Plan.LifecycleEvent'; Value = 'Leaver' } }
    }
  )
}
'@

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner'
            $providers = @{
                StepRegistry = @{ 'IdLE.Step.StrictSchemaTest' = 'Invoke-IdleTestNoopStep' }
                StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.StrictSchemaTest') -WithSchemas @{
                    'IdLE.Step.StrictSchemaTest' = @{ RequiredKeys = @('IdentityKey'); OptionalKeys = @() }
                }
            }

            # Must not throw despite the required With.IdentityKey being absent
            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

            $plan | Should -Not -BeNullOrEmpty
            @($plan.Steps).Count | Should -Be 1
            $plan.Steps[0].Status | Should -Be 'NotApplicable'
        }

        It 'still enforces With template resolution and WithSchema validation when condition is true' {
            $wfPath = New-IdleTestWorkflowFile -FileName 'condition-applicable-schema.psd1' -Content @'
@{
  Name           = 'Condition Applicable Schema'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name      = 'StrictStep'
      Type      = 'IdLE.Step.StrictApplicableTest'
      Condition = @{ Equals = @{ Path = 'Plan.LifecycleEvent'; Value = 'Joiner' } }
    }
  )
}
'@

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner'
            $providers = @{
                StepRegistry = @{ 'IdLE.Step.StrictApplicableTest' = 'Invoke-IdleTestNoopStep' }
                StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.StrictApplicableTest') -WithSchemas @{
                    'IdLE.Step.StrictApplicableTest' = @{ RequiredKeys = @('IdentityKey'); OptionalKeys = @() }
                }
            }

            # Must still throw because condition is true and required With.IdentityKey is missing
            { New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers } |
                Should -Throw -ExpectedMessage '*IdentityKey*'
        }

        It 'does not fail planning when condition is false for an OnFailureStep referencing missing template data' {
            $wfPath = New-IdleTestWorkflowFile -FileName 'condition-skip-onfailure.psd1' -Content @'
@{
  Name           = 'Condition Skip OnFailureStep'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{ Name = 'Primary'; Type = 'IdLE.Step.PrimarySkipTest' }
  )
  OnFailureSteps = @(
    @{
      Name      = 'SkippedOnFailure'
      Type      = 'IdLE.Step.OnFailureSkipTest'
      Condition = @{ Equals = @{ Path = 'Plan.LifecycleEvent'; Value = 'Leaver' } }
      With      = @{
        Value = '{{Request.Intent.MissingKey}}'
      }
    }
  )
}
'@

            $req = New-IdleTestRequest -LifecycleEvent 'Joiner'
            $providers = @{
                StepRegistry = @{
                    'IdLE.Step.PrimarySkipTest'   = 'Invoke-IdleTestNoopStep'
                    'IdLE.Step.OnFailureSkipTest' = 'Invoke-IdleTestNoopStep'
                }
                StepMetadata = New-IdleTestStepMetadata -StepTypes @(
                    'IdLE.Step.PrimarySkipTest',
                    'IdLE.Step.OnFailureSkipTest'
                )
            }

            # Must not throw despite template referencing absent data
            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

            $plan | Should -Not -BeNullOrEmpty
            @($plan.OnFailureSteps).Count | Should -Be 1
            $plan.OnFailureSteps[0].Status | Should -Be 'NotApplicable'
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

        It 'fails plan building when PruneEntitlementsEnsureKeep step contains unsupported With.KeepPattern key (not in WithSchema.OptionalKeys)' {
            $wfPath = New-IdleTestWorkflowFile -FileName 'leaver-bad.psd1' -Content @'
@{
  Name           = 'Leaver - Bad KeepPattern'
  LifecycleEvent = 'Leaver'
  Steps          = @(
    @{
      Name = 'Prune with forbidden KeepPattern'
      Type = 'IdLE.Step.PruneEntitlementsEnsureKeep'
      With = @{
        IdentityKey = 'user1'
        Kind        = 'Group'
        Provider    = 'AD'
        KeepPattern = @('CN=*')
      }
    }
  )
}
'@

            $req = New-IdleTestRequest -LifecycleEvent 'Leaver'
            $adProvider = [pscustomobject]@{}
            $adProvider | Add-Member -MemberType ScriptMethod -Name GetCapabilities -Value { @('IdLE.Entitlement.Prune','IdLE.Entitlement.List','IdLE.Entitlement.Revoke','IdLE.Entitlement.Grant') }
            $providers = @{ AD = $adProvider }

            { New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers } |
                Should -Throw -ExpectedMessage '*KeepPattern*'
        }
    }
}

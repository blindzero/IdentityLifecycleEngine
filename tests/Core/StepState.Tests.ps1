Set-StrictMode -Version Latest

BeforeAll {
    . (Join-Path (Split-Path -Path $PSScriptRoot -Parent) '_testHelpers.ps1')
    Import-IdleTestModule

    # Producer: publishes With.Publish as State, or $global:IdleStateTestOutput when set (non-data values).
    function global:Invoke-IdleStateTestProducer {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)] [hashtable] $With
        )

        if ($null -ne $global:IdleStateTestOutput) {
            return $global:IdleStateTestOutput
        }
        return @{ State = $With['Publish'] }
    }

    # Consumer: records the With it receives.
    function global:Invoke-IdleStateTestConsumer {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)] [hashtable] $With,
            [Parameter(Mandatory)] [object] $Step
        )

        $global:IdleStateTestConsumed[$Step.Name] = $With
        return $null
    }

    # Step without StateSchema that returns State anyway.
    function global:Invoke-IdleStateTestUndeclared {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)] [hashtable] $With
        )

        return @{ State = @{ Value = 'x' } }
    }

    function global:Invoke-IdleStateTestFail {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)] [hashtable] $With
        )

        throw 'Simulated failure.'
    }

    function New-StateTestProviders {
        param([hashtable] $ProducerStateSchema)

        if ($null -eq $ProducerStateSchema) {
            $ProducerStateSchema = @{
                Keys = @{
                    Mailbox = @{ Type = 'Any'; Required = $true }
                    Count   = @{ Type = 'Int' }
                }
            }
        }

        return @{
            StepRegistry = @{
                'Test.IdLE.Step.Produce'    = 'Invoke-IdleStateTestProducer'
                'Test.IdLE.Step.Consume'    = 'Invoke-IdleStateTestConsumer'
                'Test.IdLE.Step.Undeclared' = 'Invoke-IdleStateTestUndeclared'
                'Test.IdLE.Step.Fail'       = 'Invoke-IdleStateTestFail'
            }
            StepMetadata = @{
                'Test.IdLE.Step.Produce'    = @{
                    RequiredCapabilities = @()
                    WithSchema           = @{ Keys = @{ Publish = @{ Type = 'Hashtable' } } }
                    StateSchema          = $ProducerStateSchema
                }
                'Test.IdLE.Step.Consume'    = @{
                    RequiredCapabilities = @()
                    WithSchema           = @{
                        Keys = @{
                            Value  = @{ Type = 'String' }
                            Number = @{ Type = 'Int' }
                            Items  = @{ Type = 'Array'; Items = @{ Type = 'String' } }
                        }
                    }
                }
                'Test.IdLE.Step.Undeclared' = @{
                    RequiredCapabilities = @()
                    WithSchema           = @{ Keys = @{} }
                }
                'Test.IdLE.Step.Fail'       = @{
                    RequiredCapabilities = @()
                    WithSchema           = @{ Keys = @{} }
                }
            }
        }
    }

    function New-StateTestPlan {
        param(
            [Parameter(Mandatory)] [string] $Steps,
            [Parameter()] [string] $OnFailureSteps = '@()',
            [Parameter()] [hashtable] $Intent = @{ Text = 'hello' },
            [Parameter()] [hashtable] $Providers = (New-StateTestProviders)
        )

        $wfPath = New-IdleTestWorkflowFile -FileName 'step-state.psd1' -Content @"
@{
  Name           = 'State'
  LifecycleEvent = 'Joiner'
  Steps          = $Steps
  OnFailureSteps = $OnFailureSteps
}
"@
        return New-IdlePlan -WorkflowPath $wfPath -Request (New-IdleTestRequest -LifecycleEvent 'Joiner' -Intent $Intent) -Providers $Providers
    }

    function Invoke-StateTestWorkflow {
        param(
            [Parameter(Mandatory)] [string] $Steps,
            [Parameter()] [string] $OnFailureSteps = '@()',
            [Parameter()] [hashtable] $Intent = @{ Text = 'hello' }
        )

        $providers = New-StateTestProviders
        $plan = New-StateTestPlan -Steps $Steps -OnFailureSteps $OnFailureSteps -Intent $Intent -Providers $providers
        return Invoke-IdlePlan -Plan $plan -Providers $providers
    }

    $script:ProduceStep = "@{ Name = 'Produce'; Type = 'Test.IdLE.Step.Produce'; With = @{ Publish = @{ Mailbox = @{ Type = 'UserMailbox'; Smtp = 'a@contoso.com' }; Count = 5 } } }"
}

AfterAll {
    Remove-Item -Path 'Function:\Invoke-IdleStateTestProducer', 'Function:\Invoke-IdleStateTestConsumer', 'Function:\Invoke-IdleStateTestUndeclared', 'Function:\Invoke-IdleStateTestFail' -ErrorAction SilentlyContinue
    Remove-Variable -Name 'IdleStateTestOutput', 'IdleStateTestConsumed' -Scope Global -ErrorAction SilentlyContinue
}

Describe 'Step State' {

    BeforeEach {
        $global:IdleStateTestOutput = $null
        $global:IdleStateTestConsumed = @{}
    }

    Context 'StateSchema in the step metadata' {

        It 'rejects a StateSchema without Keys (InvalidStateSchema)' {
            $providers = New-StateTestProviders -ProducerStateSchema @{ AllowAdditionalKeys = $true }
            { New-StateTestPlan -Steps "@( $script:ProduceStep )" -Providers $providers } |
                Should -Throw '*InvalidStateSchema*StateSchema is missing*Keys*'
        }

        It 'rejects an invalid key schema (InvalidStateSchema)' {
            $providers = New-StateTestProviders -ProducerStateSchema @{ Keys = @{ Mailbox = @{ Type = 'Object' } } }
            { New-StateTestPlan -Steps "@( $script:ProduceStep )" -Providers $providers } |
                Should -Throw '*InvalidStateSchema*StateSchema.Keys.Mailbox.Type*'
        }

        It 'carries the StateSchema on the plan step' {
            $plan = New-StateTestPlan -Steps "@( $script:ProduceStep )"
            $plan.Steps[0].StateSchema.Type | Should -Be 'Hashtable'
            $plan.Steps[0].StateSchema.Keys.Keys | Should -Contain 'Mailbox'
        }
    }

    Context 'Planning validation' {

        It 'rejects State references in Condition (StateReferenceNotAllowed)' {
            $steps = "@( $script:ProduceStep, @{ Name = 'C'; Type = 'Test.IdLE.Step.Consume'; Condition = @{ Exists = 'State.Produce.Mailbox' } } )"
            { New-StateTestPlan -Steps $steps } | Should -Throw '*StateReferenceNotAllowed*Condition*'
        }

        It 'rejects a reference to an unknown step (StateReferenceUnknownStep)' {
            $steps = "@( $script:ProduceStep, @{ Name = 'C'; Type = 'Test.IdLE.Step.Consume'; With = @{ Value = '{{State.Missing.Mailbox}}' } } )"
            { New-StateTestPlan -Steps $steps } | Should -Throw "*StateReferenceUnknownStep*no step named 'Missing'*"
        }

        It 'rejects a reference to a step that runs later (StateReferenceUnknownStep)' {
            $steps = "@( @{ Name = 'C'; Type = 'Test.IdLE.Step.Consume'; Precondition = @{ Exists = 'State.Produce.Mailbox' } }, $script:ProduceStep )"
            { New-StateTestPlan -Steps $steps } | Should -Throw "*StateReferenceUnknownStep*'Produce' runs before it*"
        }

        It 'rejects a reference to the step itself (StateReferenceUnknownStep)' {
            $steps = "@( @{ Name = 'Produce'; Type = 'Test.IdLE.Step.Produce'; Precondition = @{ Exists = 'State.Produce.Mailbox' } } )"
            { New-StateTestPlan -Steps $steps } | Should -Throw '*StateReferenceUnknownStep*'
        }

        It 'rejects a step name that is not an identifier (StateReferenceInvalid)' {
            $steps = "@( @{ Name = 'Get mailbox'; Type = 'Test.IdLE.Step.Produce'; With = @{ Publish = @{ Mailbox = 'x' } } }, @{ Name = 'C'; Type = 'Test.IdLE.Step.Consume'; Precondition = @{ Exists = 'State.Get mailbox.Mailbox' } } )"
            { New-StateTestPlan -Steps $steps } | Should -Throw '*StateReferenceInvalid*must be an identifier*'
        }

        It 'rejects a reference without step name (StateReferenceInvalid)' {
            $steps = "@( $script:ProduceStep, @{ Name = 'C'; Type = 'Test.IdLE.Step.Consume'; Precondition = @{ Exists = 'State' } } )"
            { New-StateTestPlan -Steps $steps } | Should -Throw '*StateReferenceInvalid*'
        }

        It 'rejects a reference to a step without StateSchema (StateReferenceNotDeclared)' {
            $steps = "@( @{ Name = 'U'; Type = 'Test.IdLE.Step.Undeclared' }, @{ Name = 'C'; Type = 'Test.IdLE.Step.Consume'; With = @{ Value = '{{State.U.Value}}' } } )"
            { New-StateTestPlan -Steps $steps } | Should -Throw '*StateReferenceNotDeclared*declares no StateSchema*'
        }

        It 'rejects an undeclared State key (StateReferenceNotDeclared)' {
            $steps = "@( $script:ProduceStep, @{ Name = 'C'; Type = 'Test.IdLE.Step.Consume'; With = @{ Value = '{{State.Produce.Other}}' } } )"
            { New-StateTestPlan -Steps $steps } | Should -Throw "*StateReferenceNotDeclared*does not declare 'Other'*Count, Mailbox*"
        }

        It 'rejects an OnFailureSteps reference to a name used in both collections (StateReferenceAmbiguous)' {
            $onFailure = "@( @{ Name = 'Produce'; Type = 'Test.IdLE.Step.Produce'; With = @{ Publish = @{ Mailbox = 'x' } } }, @{ Name = 'C'; Type = 'Test.IdLE.Step.Consume'; With = @{ Value = '{{State.Produce.Mailbox.Type}}' } } )"
            { New-StateTestPlan -Steps "@( $script:ProduceStep )" -OnFailureSteps $onFailure } | Should -Throw '*StateReferenceAmbiguous*'
        }

        It 'rejects State in the provider routing keys (StateReferenceNotAllowed)' {
            $providers = New-StateTestProviders
            $providers.StepMetadata['Test.IdLE.Step.Consume'].Provider = @{ DefaultAlias = 'Identity' }
            $steps = "@( $script:ProduceStep, @{ Name = 'C'; Type = 'Test.IdLE.Step.Consume'; With = @{ AuthSessionName = '{{State.Produce.Mailbox.Type}}' } } )"
            { New-StateTestPlan -Steps $steps -Providers $providers } | Should -Throw '*StateReferenceNotAllowed*With.AuthSessionName*'
        }

        It 'fails planning when a Request placeholder of a deferred string does not resolve' {
            $steps = "@( $script:ProduceStep, @{ Name = 'C'; Type = 'Test.IdLE.Step.Consume'; With = @{ Value = '{{Request.Intent.Missing}}-{{State.Produce.Mailbox.Type}}' } } )"
            { New-StateTestPlan -Steps $steps } | Should -Throw "*Request.Intent.Missing*resolved to null*"
        }

        It 'keeps deferred strings verbatim in the plan and records them in DeferredWith' {
            $steps = "@( $script:ProduceStep, @{ Name = 'C'; Type = 'Test.IdLE.Step.Consume'; With = @{ Value = '{{Request.Intent.Text}}:{{State.Produce.Mailbox.Smtp}}'; Number = '{{State.Produce.Count}}'; Items = @('static', '{{State.Produce.Mailbox.Type}}') } } )"
            $plan = New-StateTestPlan -Steps $steps

            $consumer = $plan.Steps[1]
            $consumer.With.Value | Should -Be '{{Request.Intent.Text}}:{{State.Produce.Mailbox.Smtp}}'
            $consumer.With.Number | Should -Be '{{State.Produce.Count}}'
            @($consumer.DeferredWith.Path) | Should -Be @('With.Items[1]', 'With.Number', 'With.Value') -Because 'every deferred string is recorded'
            ($consumer.DeferredWith | Where-Object Path -eq 'With.Number').Schema.Type | Should -Be 'Int'
            ($consumer.DeferredWith | Where-Object Path -eq 'With.Items[1]').Schema.Type | Should -Be 'String'

            $json = Export-IdlePlan -Plan $plan
            $json | Should -Match ([regex]::Escape('{{State.Produce.Count}}'))
        }

        It 'does not defer strings without State placeholders' {
            $steps = "@( $script:ProduceStep, @{ Name = 'C'; Type = 'Test.IdLE.Step.Consume'; With = @{ Value = '{{Request.Intent.Text}}' } } )"
            $plan = New-StateTestPlan -Steps $steps
            $plan.Steps[1].With.Value | Should -Be 'hello'
            @($plan.Steps[1].DeferredWith).Count | Should -Be 0
        }
    }

    Context 'Execution' {

        It 'passes State to later steps via With templates and Preconditions' {
            $steps = @"
@(
  $script:ProduceStep
  @{
    Name         = 'C'
    Type         = 'Test.IdLE.Step.Consume'
    Precondition = @{ Equals = @{ Path = 'State.Produce.Mailbox.Type'; Value = 'UserMailbox' } }
    With         = @{ Value = '{{Request.Intent.Text}}:{{State.Produce.Mailbox.Smtp}}'; Number = '{{State.Produce.Count}}' }
  }
)
"@
            $result = Invoke-StateTestWorkflow -Steps $steps

            $result.Status | Should -Be 'Completed'
            $result.Steps[0].State.Count | Should -Be 5
            $global:IdleStateTestConsumed['C'].Value | Should -Be 'hello:a@contoso.com'
            $global:IdleStateTestConsumed['C'].Number | Should -Be 5
            $global:IdleStateTestConsumed['C'].Number | Should -BeOfType [int]
        }

        It 'does not modify the plan step when resolving deferred With' {
            $providers = New-StateTestProviders
            $plan = New-StateTestPlan -Providers $providers -Steps "@( $script:ProduceStep, @{ Name = 'C'; Type = 'Test.IdLE.Step.Consume'; With = @{ Number = '{{State.Produce.Count}}' } } )"
            $null = Invoke-IdlePlan -Plan $plan -Providers $providers
            $plan.Steps[1].With.Number | Should -Be '{{State.Produce.Count}}'
        }

        It 'never resolves State placeholders that come from request data' {
            $steps = "@( $script:ProduceStep, @{ Name = 'C'; Type = 'Test.IdLE.Step.Consume'; With = @{ Value = '{{Request.Intent.Text}}|{{State.Produce.Count}}' } } )"
            $result = Invoke-StateTestWorkflow -Steps $steps -Intent @{ Text = '{{State.Produce.Mailbox.Smtp}}' }

            $result.Status | Should -Be 'Completed'
            $global:IdleStateTestConsumed['C'].Value | Should -Be '{{State.Produce.Mailbox.Smtp}}|5'
        }

        It 'lets a Precondition with Exists skip a step whose producer did not run' {
            $steps = @"
@(
  @{ Name = 'Produce'; Type = 'Test.IdLE.Step.Produce'; Condition = @{ Equals = @{ Path = 'Request.LifecycleEvent'; Value = 'Leaver' } }; With = @{ Publish = @{ Mailbox = 'x' } } }
  @{
    Name                = 'C'
    Type                = 'Test.IdLE.Step.Consume'
    Precondition        = @{ All = @( @{ Exists = 'State.Produce.Mailbox' }, @{ Equals = @{ Path = 'State.Produce.Mailbox'; Value = 'x' } } ) }
    OnPreconditionFalse = 'Continue'
  }
)
"@
            $result = Invoke-StateTestWorkflow -Steps $steps

            $result.Status | Should -Be 'Completed'
            $result.Steps[0].Status | Should -Be 'NotApplicable'
            $result.Steps[1].Status | Should -Be 'PreconditionSkipped'
            $global:IdleStateTestConsumed.ContainsKey('C') | Should -BeFalse
        }

        It 'fails the step when a With template references State of a producer that did not run (StateReferenceUnresolved)' {
            $steps = @"
@(
  @{ Name = 'Produce'; Type = 'Test.IdLE.Step.Produce'; Condition = @{ Equals = @{ Path = 'Request.LifecycleEvent'; Value = 'Leaver' } }; With = @{ Publish = @{ Mailbox = 'x' } } }
  @{ Name = 'C'; Type = 'Test.IdLE.Step.Consume'; With = @{ Value = '{{State.Produce.Mailbox}}' } }
)
"@
            $result = Invoke-StateTestWorkflow -Steps $steps

            $result.Status | Should -Be 'Failed'
            $result.Steps[1].Status | Should -Be 'Failed'
            $result.Steps[1].Error | Should -Match 'StateReferenceUnresolved'
        }

        It 'validates a resolved deferred value against its key schema (WithKeyTypeMismatch)' {
            $steps = "@( $script:ProduceStep, @{ Name = 'C'; Type = 'Test.IdLE.Step.Consume'; With = @{ Number = '{{State.Produce.Mailbox.Type}}' } } )"
            $result = Invoke-StateTestWorkflow -Steps $steps

            $result.Steps[1].Status | Should -Be 'Failed'
            $result.Steps[1].Error | Should -Match 'WithKeyTypeMismatch.*With\.Number must be an Int'
        }

        It 'gives OnFailureSteps the State of completed steps' {
            $steps = "@( $script:ProduceStep, @{ Name = 'Boom'; Type = 'Test.IdLE.Step.Fail' } )"
            $onFailure = "@( @{ Name = 'Cleanup'; Type = 'Test.IdLE.Step.Consume'; With = @{ Value = '{{State.Produce.Mailbox.Smtp}}' } } )"
            $result = Invoke-StateTestWorkflow -Steps $steps -OnFailureSteps $onFailure

            $result.Status | Should -Be 'Failed'
            $result.OnFailure.Status | Should -Be 'Completed'
            $global:IdleStateTestConsumed['Cleanup'].Value | Should -Be 'a@contoso.com'
        }

        It 'publishes StateSchema defaults when the handler returns no State' {
            $providers = New-StateTestProviders -ProducerStateSchema @{ Keys = @{ Mailbox = @{ Type = 'String'; Default = 'none' } } }
            $steps = "@( @{ Name = 'Produce'; Type = 'Test.IdLE.Step.Produce' }, @{ Name = 'C'; Type = 'Test.IdLE.Step.Consume'; With = @{ Value = '{{State.Produce.Mailbox}}' } } )"
            $plan = New-StateTestPlan -Steps $steps -Providers $providers
            $result = Invoke-IdlePlan -Plan $plan -Providers $providers

            $result.Status | Should -Be 'Completed'
            $result.Steps[0].State.Mailbox | Should -Be 'none'
            $global:IdleStateTestConsumed['C'].Value | Should -Be 'none'
        }

        It 'publishes no State for a failed producer' {
            # Undeclared key 'Other': the producer fails with InvalidStepHandlerResult.
            $steps = "@( @{ Name = 'Produce'; Type = 'Test.IdLE.Step.Produce'; With = @{ Publish = @{ Mailbox = 'x'; Other = 1 } } } )"
            $onFailure = @"
@(
  @{ Name = 'Guarded'; Type = 'Test.IdLE.Step.Consume'; Precondition = @{ Exists = 'State.Produce.Mailbox' }; OnPreconditionFalse = 'Continue' }
  @{ Name = 'Unguarded'; Type = 'Test.IdLE.Step.Consume'; With = @{ Value = '{{State.Produce.Mailbox}}' } }
)
"@
            $result = Invoke-StateTestWorkflow -Steps $steps -OnFailureSteps $onFailure

            $result.Status | Should -Be 'Failed'
            $result.Steps[0].Status | Should -Be 'Failed'
            $result.OnFailure.Status | Should -Be 'PartiallyFailed'
            ($result.OnFailure.Steps | Where-Object Name -eq 'Guarded').Status | Should -Be 'PreconditionSkipped'
            $unguarded = $result.OnFailure.Steps | Where-Object Name -eq 'Unguarded'
            $unguarded.Status | Should -Be 'Failed'
            $unguarded.Error | Should -Match 'StateReferenceUnresolved'
            $global:IdleStateTestConsumed.Count | Should -Be 0
        }
    }

    Context 'Handler result validation' {

        It 'rejects State from a step without StateSchema (InvalidStepHandlerResult)' {
            $result = Invoke-StateTestWorkflow -Steps "@( @{ Name = 'U'; Type = 'Test.IdLE.Step.Undeclared' } )"

            $result.Steps[0].Status | Should -Be 'Failed'
            $result.Steps[0].Error | Should -Match 'InvalidStepHandlerResult.*declares no StateSchema'
        }

        It 'rejects undeclared State keys (InvalidStepHandlerResult)' {
            $result = Invoke-StateTestWorkflow -Steps "@( @{ Name = 'Produce'; Type = 'Test.IdLE.Step.Produce'; With = @{ Publish = @{ Mailbox = 'x'; Other = 1 } } } )"

            $result.Steps[0].Status | Should -Be 'Failed'
            $result.Steps[0].Error | Should -Match 'InvalidStepHandlerResult.*does not match its StateSchema.*State\.Other'
        }

        It 'rejects missing required State keys (InvalidStepHandlerResult)' {
            $result = Invoke-StateTestWorkflow -Steps "@( @{ Name = 'Produce'; Type = 'Test.IdLE.Step.Produce' } )"

            $result.Steps[0].Status | Should -Be 'Failed'
            $result.Steps[0].Error | Should -Match 'InvalidStepHandlerResult.*State\.Mailbox is required'
        }

        It 'rejects ScriptBlocks in State (InvalidStepHandlerResult)' {
            $global:IdleStateTestOutput = @{ State = @{ Mailbox = @{ Nested = { 'code' } } } }
            $result = Invoke-StateTestWorkflow -Steps "@( @{ Name = 'Produce'; Type = 'Test.IdLE.Step.Produce' } )"

            $result.Steps[0].Status | Should -Be 'Failed'
            $result.Steps[0].Error | Should -Match 'InvalidStepHandlerResult.*ScriptBlocks are not allowed.*State\.Mailbox\.Nested'
        }

        It 'rejects credential objects in State (InvalidStepHandlerResult)' {
            $secret = ConvertTo-SecureString -String 'not-a-real-secret' -AsPlainText -Force
            $global:IdleStateTestOutput = @{ State = @{ Mailbox = [pscredential]::new('user', $secret) } }
            $result = Invoke-StateTestWorkflow -Steps "@( @{ Name = 'Produce'; Type = 'Test.IdLE.Step.Produce' } )"

            $result.Steps[0].Status | Should -Be 'Failed'
            $result.Steps[0].Error | Should -Match 'InvalidStepHandlerResult.*Credential objects \(PSCredential\).*State\.Mailbox'
        }
    }
}

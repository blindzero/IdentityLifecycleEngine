Set-StrictMode -Version Latest

BeforeAll {
    . (Join-Path (Split-Path -Path $PSScriptRoot -Parent) '_testHelpers.ps1')
    Import-IdleTestModule

    function global:Invoke-IdleProvenanceTestHostStep {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)] [object] $Context,
            [Parameter(Mandatory)] [hashtable] $With,
            [Parameter(Mandatory)] [object] $Step
        )

        return $null
    }

    function global:Invoke-IdleProvenanceTestFailingStep {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)] [object] $Context,
            [Parameter(Mandatory)] [hashtable] $With,
            [Parameter(Mandatory)] [object] $Step
        )

        throw 'boom'
    }

    $script:CommonVersion = (Get-Module -Name 'IdLE.Steps.Common' -All | Select-Object -First 1).Version.ToString()
    $script:MockVersion = (Get-Module -Name 'IdLE.Provider.Mock' -All | Select-Object -First 1).Version.ToString()

    $script:HostProvider = [pscustomobject]@{ Name = 'HostProvider' }
    $script:HostProvider | Add-Member -MemberType ScriptMethod -Name GetCapabilities -Value { @() } -Force

    function New-ProvenanceTestPlan {
        param(
            [Parameter()]
            [hashtable] $Providers = @{}
        )

        $wfPath = New-IdleTestWorkflowFile -FileName 'provenance.psd1' -Content @'
@{
  Name           = 'Provenance'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{ Name = 'Emit'; Type = 'IdLE.Step.EmitEvent'; With = @{ Message = 'Hello' } }
    @{
      Name      = 'Skipped'
      Type      = 'IdLE.Step.EmitEvent'
      Condition = @{ Equals = @{ Path = 'Plan.LifecycleEvent'; Value = 'Leaver' } }
    }
    @{ Name = 'Host'; Type = 'Test.IdLE.Step.Host' }
  )
  OnFailureSteps = @(
    @{ Name = 'Cleanup'; Type = 'IdLE.Step.EmitEvent'; With = @{ Message = 'Cleanup' } }
  )
}
'@
        $req = New-IdleTestRequest -LifecycleEvent 'Joiner'
        return New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $Providers
    }

    function New-ProvenanceTestProviders {
        param(
            [Parameter(Mandatory)]
            [string] $HostHandler
        )

        return @{
            Identity     = New-IdleMockIdentityProvider
            Host         = $script:HostProvider
            Dummy        = $true
            StepRegistry = @{ 'Test.IdLE.Step.Host' = $HostHandler }
            StepMetadata = New-IdleTestStepMetadata -StepTypes @('Test.IdLE.Step.Host')
        }
    }
}

AfterAll {
    Remove-Item -Path 'Function:\Invoke-IdleProvenanceTestHostStep' -ErrorAction SilentlyContinue
    Remove-Item -Path 'Function:\Invoke-IdleProvenanceTestFailingStep' -ErrorAction SilentlyContinue
}

Describe 'Provenance of step handlers and providers' {
    Context 'Plan' {
        It 'records handler sources with module and version' {
            $plan = New-ProvenanceTestPlan -Providers (New-ProvenanceTestProviders -HostHandler 'Invoke-IdleProvenanceTestHostStep')

            $source = $plan.Steps[0].Source
            $source.Module | Should -Be 'IdLE.Steps.Common'
            $source.Version | Should -Be $script:CommonVersion

            $plan.OnFailureSteps[0].Source.Module | Should -Be 'IdLE.Steps.Common'
        }

        It 'records host handlers without a module as unknown' {
            $plan = New-ProvenanceTestPlan -Providers (New-ProvenanceTestProviders -HostHandler 'Invoke-IdleProvenanceTestHostStep')

            $source = $plan.Steps[2].Source
            $source.Module | Should -BeNullOrEmpty
            $source.Version | Should -BeNullOrEmpty
        }

        It 'records an unknown source when the handler is only registered at execution time' {
            $providers = New-ProvenanceTestProviders -HostHandler 'Invoke-IdleProvenanceTestHostStep'
            $providers.Remove('StepRegistry')

            $plan = New-ProvenanceTestPlan -Providers $providers

            $plan.Steps[2].Source.Module | Should -BeNullOrEmpty
        }

        It 'records provider sources per alias (providers only, sorted)' {
            $plan = New-ProvenanceTestPlan -Providers (New-ProvenanceTestProviders -HostHandler 'Invoke-IdleProvenanceTestHostStep')

            @($plan.ProviderSources.Keys) | Should -Be @('Host', 'Identity')

            $plan.ProviderSources['Identity'].Module | Should -Be 'IdLE.Provider.Mock'
            $plan.ProviderSources['Identity'].Version | Should -Be $script:MockVersion

            $plan.ProviderSources['Host'].Module | Should -BeNullOrEmpty
        }
    }

    Context 'Execution result' {
        It 'records the source of each executed handler and $null for steps that did not run' {
            $providers = New-ProvenanceTestProviders -HostHandler 'Invoke-IdleProvenanceTestHostStep'
            $plan = New-ProvenanceTestPlan -Providers $providers

            $result = Invoke-IdlePlan -Plan $plan -Providers $providers

            $result.Status | Should -Be 'Completed'
            $result.Steps[0].Source.Module | Should -Be 'IdLE.Steps.Common'
            $result.Steps[1].Status | Should -Be 'NotApplicable'
            $result.Steps[1].Source | Should -BeNullOrEmpty
            $result.Steps[2].Source.Module | Should -BeNullOrEmpty

            $result.ProviderSources['Identity'].Module | Should -Be 'IdLE.Provider.Mock'
            $result.ProviderSources.Contains('StepRegistry') | Should -BeFalse
        }

        It 'records sources for failed steps and OnFailure steps' {
            $providers = New-ProvenanceTestProviders -HostHandler 'Invoke-IdleProvenanceTestFailingStep'
            $plan = New-ProvenanceTestPlan -Providers $providers

            $result = Invoke-IdlePlan -Plan $plan -Providers $providers

            $result.Status | Should -Be 'Failed'
            $result.Steps[2].Status | Should -Be 'Failed'
            $result.OnFailure.Steps[0].Source.Module | Should -Be 'IdLE.Steps.Common'
        }
    }

    Context 'Plan export' {
        It 'exports step and provider sources' {
            $plan = New-ProvenanceTestPlan -Providers (New-ProvenanceTestProviders -HostHandler 'Invoke-IdleProvenanceTestHostStep')

            $json = $plan | Export-IdlePlan | ConvertFrom-Json

            $json.schemaVersion | Should -Be '1.1'
            $json.plan.steps[0].source.module | Should -Be 'IdLE.Steps.Common'
            $json.plan.steps[0].source.version | Should -Be $script:CommonVersion

            @($json.plan.providers).Count | Should -Be 2
            $json.plan.providers[1].alias | Should -Be 'Identity'
            $json.plan.providers[1].module | Should -Be 'IdLE.Provider.Mock'
        }
    }
}

Set-StrictMode -Version Latest

BeforeAll {
    . (Join-Path (Split-Path -Path $PSScriptRoot -Parent) '_testHelpers.ps1')
    Import-IdleTestModule

    function global:Invoke-IdleTestProviderFallbackStep {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [ValidateNotNull()]
            [object] $Context,

            [Parameter(Mandatory)]
            [ValidateNotNull()]
            [object] $Step
        )

        if ($null -eq $Context.Providers) {
            throw 'Context.Providers must be a hashtable.'
        }

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
    Remove-Item -Path 'Function:\Invoke-IdleTestProviderFallbackStep' -ErrorAction SilentlyContinue
}

Describe 'Invoke-IdlePlan Provider Fallback' {
    BeforeEach {
        $script:WorkflowPath = New-IdleTestWorkflowFile -FileName 'joiner.psd1' -Content @'
@{
    Name           = 'Joiner - Standard'
    LifecycleEvent = 'Joiner'
    Steps          = @(
        @{ Name = 'TestStep'; Type = 'IdLE.Step.Test' }
    )
}
'@

        $script:Request = New-IdleTestRequest -LifecycleEvent 'Joiner'

        $script:BaseProviders = @{
            StepRegistry = @{
                'IdLE.Step.Test' = 'Invoke-IdleTestProviderFallbackStep'
            }
            StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.Test')
        }
    }

    Context 'Provider selection' {
        It 'uses Plan.Providers when -Providers is not supplied' {
            $plan = New-IdlePlan -WorkflowPath $script:WorkflowPath -Request $script:Request -Providers $script:BaseProviders

            $result = Invoke-IdlePlan -Plan $plan

            $result.PSTypeNames | Should -Contain 'IdLE.ExecutionResult'
            $result.Status | Should -Be 'Completed'
            $result.Steps[0].Status | Should -Be 'Completed'
        }

        It 'explicit -Providers overrides Plan.Providers' {
            $planProviders = $script:BaseProviders.Clone()
            $planProviders.TestMarker = 'PlanProviders'

            $explicitProviders = $script:BaseProviders.Clone()
            $explicitProviders.TestMarker = 'ExplicitProviders'

            $plan = New-IdlePlan -WorkflowPath $script:WorkflowPath -Request $script:Request -Providers $planProviders

            $result = Invoke-IdlePlan -Plan $plan -Providers $explicitProviders

            $result.PSTypeNames | Should -Contain 'IdLE.ExecutionResult'
            $result.Status | Should -Be 'Completed'
            $result.Providers.TestMarker | Should -Be 'ExplicitProviders'
        }

        It 'fails with clear error when neither -Providers nor Plan.Providers exist' {
            $plan = New-IdlePlan -WorkflowPath $script:WorkflowPath -Request $script:Request -Providers $script:BaseProviders
            $plan.PSObject.Properties.Remove('Providers')

            { Invoke-IdlePlan -Plan $plan } | Should -Throw '*Providers are required*'
        }

        It 'uses Plan.Providers when it is a PSCustomObject' {
            $providersObject = [pscustomobject]$script:BaseProviders

            $plan = New-IdlePlan -WorkflowPath $script:WorkflowPath -Request $script:Request -Providers $providersObject

            $result = Invoke-IdlePlan -Plan $plan

            $result.PSTypeNames | Should -Contain 'IdLE.ExecutionResult'
            $result.Status | Should -Be 'Completed'
            $result.Steps[0].Status | Should -Be 'Completed'
        }
    }

    Context 'Regression coverage' {
        It 'does not fail with "Context.Providers must be a hashtable" when using Plan.Providers' {
            $plan = New-IdlePlan -WorkflowPath $script:WorkflowPath -Request $script:Request -Providers $script:BaseProviders

            { Invoke-IdlePlan -Plan $plan } | Should -Not -Throw
        }
    }

    Context 'Security validation' {
        It 'applies security validations to Plan.Providers' {
            $providers = $script:BaseProviders.Clone()
            $providers.MaliciousCode = { Write-Host 'Malicious' }

            $plan = New-IdlePlan -WorkflowPath $script:WorkflowPath -Request $script:Request -Providers $providers

            { Invoke-IdlePlan -Plan $plan } | Should -Throw
        }
    }

    Context 'Redaction' {
        It 'redacts Plan.Providers in execution result when used as fallback' {
            $providers = $script:BaseProviders.Clone()
            $providers.TestProvider = @{
                endpoint = 'https://example.test'
                token    = 'SecretToken123'
                apiKey   = 'ApiKey456'
            }

            $plan = New-IdlePlan -WorkflowPath $script:WorkflowPath -Request $script:Request -Providers $providers

            $result = Invoke-IdlePlan -Plan $plan

            $result.Status | Should -Be 'Completed'
            $result.Providers | Should -Not -BeNullOrEmpty
            $result.Providers.TestProvider.token | Should -Be '[REDACTED]'
            $result.Providers.TestProvider.apiKey | Should -Be '[REDACTED]'
            $result.Providers.TestProvider.endpoint | Should -Be 'https://example.test'
        }
    }
}

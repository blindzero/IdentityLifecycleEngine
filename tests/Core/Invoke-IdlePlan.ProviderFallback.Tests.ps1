BeforeAll {
    . (Join-Path (Split-Path -Path $PSScriptRoot -Parent) '_testHelpers.ps1')
    Import-IdleTestModule

    # Test step handler for provider fallback tests
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

        # Verify Context.Providers is not null (reproduces the original failure scenario)
        if ($null -eq $Context.Providers) {
            throw "Context.Providers must be a hashtable."
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
    It 'uses Plan.Providers when -Providers is not supplied' {
        $wfPath = Join-Path -Path $TestDrive -ChildPath 'joiner.psd1'
        Set-Content -Path $wfPath -Encoding UTF8 -Value @'
@{
  Name           = 'Joiner - Standard'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{ Name = 'TestStep'; Type = 'IdLE.Step.Test' }
  )
}
'@

        $req = New-IdleLifecycleRequest -LifecycleEvent 'Joiner'

        $providers = @{
            StepRegistry = @{
                'IdLE.Step.Test' = 'Invoke-IdleTestProviderFallbackStep'
            }
            StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.Test')
        }

        # Build plan with providers
        $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

        # Execute without passing -Providers (should use Plan.Providers)
        $result = Invoke-IdlePlan -Plan $plan

        $result.PSTypeNames | Should -Contain 'IdLE.ExecutionResult'
        $result.Status | Should -Be 'Completed'
        $result.Steps[0].Status | Should -Be 'Completed'
    }

    It 'explicit -Providers overrides Plan.Providers' {
        $wfPath = Join-Path -Path $TestDrive -ChildPath 'joiner.psd1'
        Set-Content -Path $wfPath -Encoding UTF8 -Value @'
@{
  Name           = 'Joiner - Standard'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{ Name = 'TestStep'; Type = 'IdLE.Step.Test' }
  )
}
'@

        $req = New-IdleLifecycleRequest -LifecycleEvent 'Joiner'

        $planProviders = @{
            StepRegistry = @{
                'IdLE.Step.Test' = 'Invoke-IdleTestProviderFallbackStep'
            }
            StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.Test')
            TestMarker   = 'PlanProviders'
        }

        $explicitProviders = @{
            StepRegistry = @{
                'IdLE.Step.Test' = 'Invoke-IdleTestProviderFallbackStep'
            }
            StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.Test')
            TestMarker   = 'ExplicitProviders'
        }

        # Build plan with planProviders
        $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $planProviders

        # Execute with explicit providers (should override Plan.Providers)
        $result = Invoke-IdlePlan -Plan $plan -Providers $explicitProviders

        $result.PSTypeNames | Should -Contain 'IdLE.ExecutionResult'
        $result.Status | Should -Be 'Completed'
        # Verify that explicitProviders were used (check redacted providers)
        $result.Providers.TestMarker | Should -Be 'ExplicitProviders'
    }

    It 'fails with clear error when neither -Providers nor Plan.Providers exist' {
        $wfPath = Join-Path -Path $TestDrive -ChildPath 'joiner.psd1'
        Set-Content -Path $wfPath -Encoding UTF8 -Value @'
@{
  Name           = 'Joiner - Standard'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{ Name = 'TestStep'; Type = 'IdLE.Step.Test' }
  )
}
'@

        $req = New-IdleLifecycleRequest -LifecycleEvent 'Joiner'

        # Build plan with providers, then remove Providers property to simulate exported plan scenario
        $providers = @{
            StepRegistry = @{
                'IdLE.Step.Test' = 'Invoke-IdleTestProviderFallbackStep'
            }
            StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.Test')
        }
        $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

        # Remove Providers property to simulate an exported plan without provider objects
        $plan.PSObject.Properties.Remove('Providers')

        # Execute without -Providers and without Plan.Providers
        { Invoke-IdlePlan -Plan $plan } | Should -Throw '*Providers are required*'
    }

    It 'regression: does not fail with "Context.Providers must be a hashtable" when using Plan.Providers' {
        $wfPath = Join-Path -Path $TestDrive -ChildPath 'joiner.psd1'
        Set-Content -Path $wfPath -Encoding UTF8 -Value @'
@{
  Name           = 'Joiner - Standard'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{ Name = 'TestStep'; Type = 'IdLE.Step.Test' }
  )
}
'@

        $req = New-IdleLifecycleRequest -LifecycleEvent 'Joiner'

        $providers = @{
            StepRegistry = @{
                'IdLE.Step.Test' = 'Invoke-IdleTestProviderFallbackStep'
            }
            StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.Test')
        }

        # Build plan with providers
        $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

        # Execute without passing -Providers (should NOT throw "Context.Providers must be a hashtable")
        { Invoke-IdlePlan -Plan $plan } | Should -Not -Throw
    }

    It 'applies security validations to Plan.Providers' {
        $wfPath = Join-Path -Path $TestDrive -ChildPath 'joiner.psd1'
        Set-Content -Path $wfPath -Encoding UTF8 -Value @'
@{
  Name           = 'Joiner - Standard'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{ Name = 'TestStep'; Type = 'IdLE.Step.Test' }
  )
}
'@

        $req = New-IdleLifecycleRequest -LifecycleEvent 'Joiner'

        $providers = @{
            StepRegistry  = @{
                'IdLE.Step.Test' = 'Invoke-IdleTestProviderFallbackStep'
            }
            StepMetadata  = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.Test')
            MaliciousCode = { Write-Host "Malicious" }  # ScriptBlock should be rejected
        }

        # Build plan with providers containing ScriptBlock
        $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

        # Execute without passing -Providers (should still reject ScriptBlocks in Plan.Providers)
        { Invoke-IdlePlan -Plan $plan } | Should -Throw
    }

    It 'redacts Plan.Providers in execution result when used as fallback' {
        $wfPath = Join-Path -Path $TestDrive -ChildPath 'joiner.psd1'
        Set-Content -Path $wfPath -Encoding UTF8 -Value @'
@{
  Name           = 'Joiner - Standard'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{ Name = 'TestStep'; Type = 'IdLE.Step.Test' }
  )
}
'@

        $req = New-IdleLifecycleRequest -LifecycleEvent 'Joiner'

        $providers = @{
            StepRegistry = @{
                'IdLE.Step.Test' = 'Invoke-IdleTestProviderFallbackStep'
            }
            StepMetadata = New-IdleTestStepMetadata -StepTypes @('IdLE.Step.Test')
            TestProvider = @{
                endpoint = 'https://example.test'
                token    = 'SecretToken123'
                apiKey   = 'ApiKey456'
            }
        }

        # Build plan with providers
        $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

        # Execute without passing -Providers
        $result = Invoke-IdlePlan -Plan $plan

        $result.Status | Should -Be 'Completed'
        # Providers should be redacted (sensitive keys should have [REDACTED])
        $result.Providers | Should -Not -BeNullOrEmpty
        $result.Providers.TestProvider.token | Should -Be '[REDACTED]'
        $result.Providers.TestProvider.apiKey | Should -Be '[REDACTED]'
        $result.Providers.TestProvider.endpoint | Should -Be 'https://example.test'
    }
}

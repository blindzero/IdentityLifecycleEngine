Set-StrictMode -Version Latest

BeforeAll {
    . (Join-Path (Split-Path -Path $PSScriptRoot -Parent) '_testHelpers.ps1')
    Import-IdleTestModule
    $script:FixturesPath = Join-Path $PSScriptRoot '..' 'fixtures/workflows'
}

Describe 'Resolve-IdleStepMetadataCatalog - step pack catalog ownership' {
    Context 'Step pack discovery' {
        It 'discovers loaded step packs exporting Get-IdleStepMetadataCatalog' {
            $commonModule = Get-Module -Name 'IdLE.Steps.Common'
            $commonModule | Should -Not -BeNullOrEmpty
            $commonModule.ExportedCommands.ContainsKey('Get-IdleStepMetadataCatalog') | Should -BeTrue

            $dirSyncModule = Get-Module -Name 'IdLE.Steps.DirectorySync'
            $dirSyncModule | Should -Not -BeNullOrEmpty
            $dirSyncModule.ExportedCommands.ContainsKey('Get-IdleStepMetadataCatalog') | Should -BeTrue

            $wfPath = Join-Path -Path $script:FixturesPath -ChildPath 'joiner-builtin.psd1'
            $req = New-IdleTestRequest -LifecycleEvent 'Joiner'

            $provider = [pscustomobject]@{ Name = 'IdentityProvider' }
            $provider | Add-Member -MemberType ScriptMethod -Name GetCapabilities -Value {
                return @('IdLE.Identity.Disable')
            } -Force

            $providers = @{
                IdentityProvider = $provider
            }

            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

            $plan.Steps[0].RequiresCapabilities | Should -Contain 'IdLE.Identity.Disable'
        }

        It 'merges catalogs from multiple step packs deterministically' {
            $wfPathDirSync = Join-Path -Path $script:FixturesPath -ChildPath 'joiner-with-dirsync.psd1'
            $req = New-IdleTestRequest -LifecycleEvent 'Joiner'

            $provider = [pscustomobject]@{ Name = 'DirSyncProvider' }
            $provider | Add-Member -MemberType ScriptMethod -Name GetCapabilities -Value {
                return @('IdLE.DirectorySync.Trigger', 'IdLE.DirectorySync.Status')
            } -Force

            $providers = @{
                DirectorySync = $provider
            }

            $plan = New-IdlePlan -WorkflowPath $wfPathDirSync -Request $req -Providers $providers

            $plan.Steps[0].Type | Should -Be 'IdLE.Step.TriggerDirectorySync'
            $plan.Steps[0].RequiresCapabilities | Should -Contain 'IdLE.DirectorySync.Trigger'
            $plan.Steps[0].RequiresCapabilities | Should -Contain 'IdLE.DirectorySync.Status'
        }
    }

    Context 'Host metadata supplements' {
        It 'allows host to supplement with new step types not in step packs' {
            $wfPath = Join-Path -Path $script:FixturesPath -ChildPath 'joiner-no-metadata.psd1'
            $req = New-IdleTestRequest -LifecycleEvent 'Joiner'

            $provider = [pscustomobject]@{ Name = 'CustomProvider' }
            $provider | Add-Member -MemberType ScriptMethod -Name GetCapabilities -Value {
                return @('Custom.Capability.Test')
            } -Force

            $providers = @{
                StepRegistry = @{
                    'Custom.Step.Unknown' = 'Invoke-CustomStepUnknown'
                }
                StepMetadata = @{
                    'Custom.Step.Unknown' = @{
                        RequiredCapabilities = @('Custom.Capability.Test')
                    }
                }
                CustomProvider = $provider
            }

            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

            $plan.Steps[0].RequiresCapabilities | Should -Contain 'Custom.Capability.Test'
        }

        It 'rejects host override attempt of step pack metadata (DuplicateStepTypeMetadata)' {
            $wfPath = Join-Path -Path $script:FixturesPath -ChildPath 'joiner-builtin.psd1'
            $req = New-IdleTestRequest -LifecycleEvent 'Joiner'

            $provider = [pscustomobject]@{ Name = 'IdentityProvider' }
            $provider | Add-Member -MemberType ScriptMethod -Name GetCapabilities -Value {
                return @('Custom.Capability.Override')
            } -Force

            $providers = @{
                IdentityProvider = $provider
                StepMetadata     = @{
                    'IdLE.Step.DisableIdentity' = @{
                        RequiredCapabilities = @('Custom.Capability.Override')
                    }
                }
            }

            try {
                New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers | Out-Null
                throw 'Expected an exception but none was thrown.'
            }
            catch {
                $_.Exception.Message | Should -Match 'DuplicateStepTypeMetadata'
                $_.Exception.Message | Should -Match 'IdLE.Step.DisableIdentity'
                $_.Exception.Message | Should -Match 'IdLE.Steps.Common'
                $_.Exception.Message | Should -Match 'supplement'
            }
        }

        It 'validates metadata does not contain ScriptBlocks (host supplement)' {
            $wfPath = Join-Path -Path $script:FixturesPath -ChildPath 'joiner-no-metadata.psd1'
            $req = New-IdleTestRequest -LifecycleEvent 'Joiner'

            $providers = @{
                StepRegistry = @{
                    'Custom.Step.Unknown' = 'Invoke-CustomStepUnknown'
                }
                StepMetadata = @{
                    'Custom.Step.Unknown' = @{
                        RequiredCapabilities = { 'Dynamic.Cap' }
                    }
                }
            }

            try {
                New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers | Out-Null
                throw 'Expected an exception but none was thrown.'
            }
            catch {
                $_.Exception.Message | Should -Match 'ScriptBlock'
            }
        }
    }
}

Describe 'New-IdlePlan - step metadata catalog integration' {
    Context 'Missing metadata' {
        It 'fails fast with MissingStepTypeMetadata when step type has no metadata' {
            $wfPath = Join-Path -Path $script:FixturesPath -ChildPath 'joiner-no-metadata.psd1'
            $req = New-IdleTestRequest -LifecycleEvent 'Joiner'

            $providers = @{
                StepRegistry = @{
                    'Custom.Step.Unknown' = 'Invoke-CustomStepUnknown'
                }
            }

            try {
                New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers | Out-Null
                throw 'Expected an exception but none was thrown.'
            }
            catch {
                $_.Exception.Message | Should -Match 'MissingStepTypeMetadata'
                $_.Exception.Message | Should -Match 'Custom.Step.Unknown'
                $_.Exception.Message | Should -Match 'Import/load the step pack'
                $_.Exception.Message | Should -Match 'Providers.StepMetadata'
            }
        }
    }

    Context 'Step pack metadata' {
        It 'derives capabilities from step pack metadata (IdLE.Step.DisableIdentity)' {
            $wfPath = Join-Path -Path $script:FixturesPath -ChildPath 'joiner-builtin.psd1'
            $req = New-IdleTestRequest -LifecycleEvent 'Joiner'

            $provider = [pscustomobject]@{ Name = 'IdentityProvider' }
            $provider | Add-Member -MemberType ScriptMethod -Name GetCapabilities -Value {
                return @('IdLE.Identity.Disable')
            } -Force

            $providers = @{
                IdentityProvider = $provider
            }

            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

            $plan | Should -Not -BeNullOrEmpty
            $plan.Steps.Count | Should -Be 1
            $plan.Steps[0].RequiresCapabilities | Should -Contain 'IdLE.Identity.Disable'
        }

        It 'derives capabilities from DirectorySync step pack (IdLE.Step.TriggerDirectorySync)' {
            $wfPath = Join-Path -Path $script:FixturesPath -ChildPath 'joiner-with-dirsync.psd1'
            $req = New-IdleTestRequest -LifecycleEvent 'Joiner'

            $provider = [pscustomobject]@{ Name = 'DirSyncProvider' }
            $provider | Add-Member -MemberType ScriptMethod -Name GetCapabilities -Value {
                return @('IdLE.DirectorySync.Trigger', 'IdLE.DirectorySync.Status')
            } -Force

            $providers = @{
                DirectorySync = $provider
            }

            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

            $plan | Should -Not -BeNullOrEmpty
            $plan.Steps.Count | Should -Be 1
            $plan.Steps[0].Type | Should -Be 'IdLE.Step.TriggerDirectorySync'
            $plan.Steps[0].RequiresCapabilities | Should -Contain 'IdLE.DirectorySync.Trigger'
            $plan.Steps[0].RequiresCapabilities | Should -Contain 'IdLE.DirectorySync.Status'
        }

        It 'validates OnFailureSteps capabilities from metadata' {
            $wfPath = Join-Path -Path $script:FixturesPath -ChildPath 'joiner-onfailure.psd1'
            $req = New-IdleTestRequest -LifecycleEvent 'Joiner'

            $provider = [pscustomobject]@{ Name = 'IdentityProvider' }
            $provider | Add-Member -MemberType ScriptMethod -Name GetCapabilities -Value {
                return @('IdLE.Identity.Disable')
            } -Force

            $providers = @{
                IdentityProvider = $provider
            }

            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

            $plan | Should -Not -BeNullOrEmpty
            $plan.OnFailureSteps.Count | Should -Be 1
            $plan.OnFailureSteps[0].RequiresCapabilities | Should -Contain 'IdLE.Identity.Disable'
        }

        It 'validates entitlement capabilities from metadata' {
            $wfPath = Join-Path -Path $script:FixturesPath -ChildPath 'joiner-entitlements.psd1'
            $req = New-IdleTestRequest -LifecycleEvent 'Joiner'

            try {
                New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers @{} | Out-Null
                throw 'Expected an exception but none was thrown.'
            }
            catch {
                $_.Exception.Message | Should -Match 'MissingCapabilities'
                $_.Exception.Message | Should -Match 'IdLE\.Entitlement'
            }

            $provider = [pscustomobject]@{ Name = 'EntProvider' }
            $provider | Add-Member -MemberType ScriptMethod -Name GetCapabilities -Value {
                return @('IdLE.Entitlement.List', 'IdLE.Entitlement.Grant', 'IdLE.Entitlement.Revoke')
            } -Force

            $providers = @{ Entitlement = $provider }

            $plan = New-IdlePlan -WorkflowPath $wfPath -Request $req -Providers $providers

            $plan | Should -Not -BeNullOrEmpty
            $plan.Steps.Count | Should -Be 1
            $plan.Steps[0].RequiresCapabilities | Should -Contain 'IdLE.Entitlement.List'
            $plan.Steps[0].RequiresCapabilities | Should -Contain 'IdLE.Entitlement.Grant'
            $plan.Steps[0].RequiresCapabilities | Should -Contain 'IdLE.Entitlement.Revoke'
        }
    }
}


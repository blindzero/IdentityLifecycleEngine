Set-StrictMode -Version Latest

BeforeDiscovery {
    . (Join-Path -Path $PSScriptRoot -ChildPath '..\_testHelpers.ps1')
    Import-IdleTestModule

    # $PSScriptRoot = ...\tests\Providers
    # repo root     = parent of ...\tests
    $testsRoot = Split-Path -Path $PSScriptRoot -Parent
    $repoRoot  = Split-Path -Path $testsRoot -Parent

    $capabilitiesContractPath = Join-Path -Path $repoRoot -ChildPath 'tests\ProviderContracts\ProviderCapabilities.Contract.ps1'
    if (-not (Test-Path -LiteralPath $capabilitiesContractPath -PathType Leaf)) {
        throw "Provider capabilities contract not found at: $capabilitiesContractPath"
    }
    . $capabilitiesContractPath
}

Describe 'Entra Connect directory sync provider contracts' {
    Invoke-IdleProviderCapabilitiesContractTests -ProviderFactory { New-IdleEntraConnectDirectorySyncProvider }

    Context 'Directory sync provider methods' {
        BeforeAll {
            $script:Provider = New-IdleEntraConnectDirectorySyncProvider

            # Mock AuthSession with InvokeCommand method
            $script:MockAuthSession = [pscustomobject]@{
                PSTypeName = 'Mock.AuthSession'
            }

            $script:MockAuthSession | Add-Member -MemberType ScriptMethod -Name InvokeCommand -Value {
                param(
                    [Parameter(Mandatory)]
                    [string] $CommandName,

                    [Parameter(Mandatory)]
                    [hashtable] $Parameters
                )

                # Mock behavior for Start-ADSyncSyncCycle
                if ($CommandName -eq 'Start-ADSyncSyncCycle') {
                    return [pscustomobject]@{
                        Result = 'Success'
                    }
                }

                # Mock behavior for Get-ADSyncScheduler
                if ($CommandName -eq 'Get-ADSyncScheduler') {
                    return [pscustomobject]@{
                        SyncCycleInProgress = $false
                        AllowedSyncCycleInterval = '00:30:00'
                        NextSyncCyclePolicyType = 'Delta'
                    }
                }

                throw "Unexpected command: $CommandName"
            } -Force
        }

        It 'Exposes StartSyncCycle method' {
            $script:Provider.PSObject.Methods.Name | Should -Contain 'StartSyncCycle'
        }

        It 'StartSyncCycle accepts PolicyType and AuthSession parameters' {
            $result = $script:Provider.StartSyncCycle('Delta', $script:MockAuthSession)

            $result | Should -Not -BeNullOrEmpty
            $result.PSObject.Properties.Name | Should -Contain 'Started'
            $result.PSObject.Properties.Name | Should -Contain 'Message'
        }

        It 'StartSyncCycle validates PolicyType' {
            { $script:Provider.StartSyncCycle('Invalid', $script:MockAuthSession) } | Should -Throw
        }

        It 'StartSyncCycle validates AuthSession implements InvokeCommand' {
            $badSession = [pscustomobject]@{ Name = 'BadSession' }
            { $script:Provider.StartSyncCycle('Delta', $badSession) } | Should -Throw -ErrorId * -ExpectedMessage '*InvokeCommand*'
        }

        It 'Exposes GetSyncCycleState method' {
            $script:Provider.PSObject.Methods.Name | Should -Contain 'GetSyncCycleState'
        }

        It 'GetSyncCycleState accepts AuthSession parameter' {
            $result = $script:Provider.GetSyncCycleState($script:MockAuthSession)

            $result | Should -Not -BeNullOrEmpty
            $result.PSObject.Properties.Name | Should -Contain 'InProgress'
            $result.PSObject.Properties.Name | Should -Contain 'State'
            $result.PSObject.Properties.Name | Should -Contain 'Details'
        }

        It 'GetSyncCycleState returns correct InProgress value' {
            $result = $script:Provider.GetSyncCycleState($script:MockAuthSession)

            $result.InProgress | Should -BeOfType [bool]
        }

        It 'GetSyncCycleState validates AuthSession implements InvokeCommand' {
            $badSession = [pscustomobject]@{ Name = 'BadSession' }
            { $script:Provider.GetSyncCycleState($badSession) } | Should -Throw -ErrorId * -ExpectedMessage '*InvokeCommand*'
        }
    }

    Context 'Provider capability advertisement' {
        BeforeAll {
            $script:Provider = New-IdleEntraConnectDirectorySyncProvider
        }

        It 'Advertises IdLE.DirectorySync.Trigger capability' {
            $caps = $script:Provider.GetCapabilities()
            $caps | Should -Contain 'IdLE.DirectorySync.Trigger'
        }

        It 'Advertises IdLE.DirectorySync.Status capability' {
            $caps = $script:Provider.GetCapabilities()
            $caps | Should -Contain 'IdLE.DirectorySync.Status'
        }

        It 'Advertises exactly 2 capabilities' {
            $caps = $script:Provider.GetCapabilities()
            $caps.Count | Should -Be 2
        }
    }
}

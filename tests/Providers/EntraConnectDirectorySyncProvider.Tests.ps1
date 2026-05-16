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

    $computerNameCredentialContractPath = Join-Path -Path $repoRoot -ChildPath 'tests\ProviderContracts\DirectorySyncProviderComputerNameCredential.Contract.ps1'
    if (-not (Test-Path -LiteralPath $computerNameCredentialContractPath -PathType Leaf)) {
        throw "Directory sync provider ComputerName+Credential contract not found at: $computerNameCredentialContractPath"
    }
    . $computerNameCredentialContractPath
}

Describe 'Entra Connect directory sync provider contracts' {
    Invoke-IdleProviderCapabilitiesContractTests -ProviderFactory { New-IdleEntraConnectDirectorySyncProvider }
    Invoke-IdleDirectorySyncProviderComputerNameCredentialContractTests -ProviderFactory { New-IdleEntraConnectDirectorySyncProvider }

    Context 'Directory sync provider methods' {
        BeforeEach {
            $script:Provider = New-IdleEntraConnectDirectorySyncProvider
            $script:ComputerName = 'ad-sync1.corp.local'
            $script:ProviderInput = @{
                ComputerName = $script:ComputerName
                PolicyType = 'Delta'
            }
            $script:MockCredential = [PSCredential]::new(
                'contoso\syncadmin',
                (ConvertTo-SecureString -String 'P@ssw0rd!' -AsPlainText -Force)
            )
            $script:MockSession = [pscustomobject]@{ Id = 1 }
            $script:Provider | Add-Member -NotePropertyName LastComputerName -NotePropertyValue $null -Force
            $script:Provider | Add-Member -NotePropertyName LastCredential -NotePropertyValue $null -Force
            $script:Provider | Add-Member -NotePropertyName RemovedSession -NotePropertyValue $null -Force

            $script:Provider | Add-Member -MemberType ScriptMethod -Name NewRemoteSession -Value {
                param([string] $ComputerName, [pscredential] $Credential)
                $this.LastComputerName = $ComputerName
                $this.LastCredential = $Credential
                return $script:MockSession
            } -Force

            $script:Provider | Add-Member -MemberType ScriptMethod -Name InvokeRemoteCommand -Value {
                param([object] $Session, [scriptblock] $ScriptBlock, [object[]] $ArgumentList)
                return [pscustomobject]@{
                    SyncCycleInProgress       = $false
                    AllowedSyncCycleInterval  = '00:30:00'
                    NextSyncCyclePolicyType   = 'Delta'
                }
            } -Force

            $script:Provider | Add-Member -MemberType ScriptMethod -Name RemoveRemoteSession -Value {
                param([object] $Session)
                $this.RemovedSession = $Session
            } -Force
        }

        It 'Exposes StartSyncCycle method' {
            $script:Provider.PSObject.Methods.Name | Should -Contain 'StartSyncCycle'
        }

        It 'StartSyncCycle accepts ProviderInput and AuthSession parameters' {
            $result = $script:Provider.StartSyncCycle($script:ProviderInput, $script:MockCredential)

            $result | Should -Not -BeNullOrEmpty
            $result.PSObject.Properties.Name | Should -Contain 'Started'
            $result.PSObject.Properties.Name | Should -Contain 'Message'
            $script:Provider.LastComputerName | Should -Be $script:ComputerName
            $script:Provider.LastCredential | Should -Be $script:MockCredential
            $script:Provider.RemovedSession | Should -Be $script:MockSession
        }

        It 'StartSyncCycle validates ProviderInput.PolicyType' {
            $providerInput = @{
                ComputerName = $script:ComputerName
                PolicyType = 'Invalid'
            }
            { $script:Provider.StartSyncCycle($providerInput, $script:MockCredential) } | Should -Throw -ErrorId * -ExpectedMessage '*PolicyType*'
        }

        It 'StartSyncCycle validates ProviderInput.ComputerName' {
            $providerInput = @{
                ComputerName = ''
                PolicyType = 'Delta'
            }
            { $script:Provider.StartSyncCycle($providerInput, $script:MockCredential) } | Should -Throw -ErrorId * -ExpectedMessage '*ComputerName*'
        }

        It 'StartSyncCycle validates AuthSession is PSCredential' {
            $badSession = [pscustomobject]@{ Name = 'BadSession' }
            { $script:Provider.StartSyncCycle($script:ProviderInput, $badSession) } | Should -Throw -ErrorId * -ExpectedMessage '*PSCredential*'
        }

        It 'StartSyncCycle always closes remoting session' {
            $script:Provider | Add-Member -MemberType ScriptMethod -Name InvokeRemoteCommand -Value {
                param([object] $Session, [scriptblock] $ScriptBlock, [object[]] $ArgumentList)
                throw 'remote failure'
            } -Force

            { $script:Provider.StartSyncCycle($script:ProviderInput, $script:MockCredential) } | Should -Throw
            $script:Provider.RemovedSession | Should -Be $script:MockSession
        }

        It 'Exposes GetSyncCycleState method' {
            $script:Provider.PSObject.Methods.Name | Should -Contain 'GetSyncCycleState'
        }

        It 'GetSyncCycleState accepts ProviderInput and AuthSession parameters' {
            $result = $script:Provider.GetSyncCycleState($script:ProviderInput, $script:MockCredential)

            $result | Should -Not -BeNullOrEmpty
            $result.PSObject.Properties.Name | Should -Contain 'InProgress'
            $result.PSObject.Properties.Name | Should -Contain 'State'
            $result.PSObject.Properties.Name | Should -Contain 'Details'
            $script:Provider.LastComputerName | Should -Be $script:ComputerName
            $script:Provider.LastCredential | Should -Be $script:MockCredential
            $script:Provider.RemovedSession | Should -Be $script:MockSession
        }

        It 'GetSyncCycleState returns correct InProgress value' {
            $result = $script:Provider.GetSyncCycleState($script:ProviderInput, $script:MockCredential)

            $result.InProgress | Should -BeOfType [bool]
        }

        It 'GetSyncCycleState validates ProviderInput.ComputerName' {
            $providerInput = @{
                ComputerName = ''
                PolicyType = 'Delta'
            }
            { $script:Provider.GetSyncCycleState($providerInput, $script:MockCredential) } | Should -Throw -ErrorId * -ExpectedMessage '*ComputerName*'
        }

        It 'GetSyncCycleState validates AuthSession is PSCredential' {
            $badSession = [pscustomobject]@{ Name = 'BadSession' }
            { $script:Provider.GetSyncCycleState($script:ProviderInput, $badSession) } | Should -Throw -ErrorId * -ExpectedMessage '*PSCredential*'
        }

        It 'GetSyncCycleState always closes remoting session' {
            $script:Provider | Add-Member -MemberType ScriptMethod -Name InvokeRemoteCommand -Value {
                param([object] $Session, [scriptblock] $ScriptBlock, [object[]] $ArgumentList)
                throw 'remote failure'
            } -Force

            { $script:Provider.GetSyncCycleState($script:ProviderInput, $script:MockCredential) } | Should -Throw
            $script:Provider.RemovedSession | Should -Be $script:MockSession
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

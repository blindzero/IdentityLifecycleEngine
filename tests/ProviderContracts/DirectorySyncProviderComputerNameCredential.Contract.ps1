Set-StrictMode -Version Latest

function Invoke-IdleDirectorySyncProviderComputerNameCredentialContractTests {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [scriptblock] $ProviderFactory
    )

    $cases = @(
        @{
            ProviderFactory = $ProviderFactory
        }
    )

    Context 'ComputerName + Credential contract' -ForEach $cases {
        BeforeEach {
            $providerFactory = $_.ProviderFactory
            if ($providerFactory -is [scriptblock]) {
                $script:Provider = & $providerFactory
            }
            elseif ($providerFactory -is [string]) {
                $script:Provider = & (Get-Command -Name $providerFactory -ErrorAction Stop)
            }
            else {
                throw "ProviderFactory must be a scriptblock or command name string. Got: $($providerFactory.GetType().FullName)"
            }
            if ($null -eq $script:Provider) {
                throw 'ProviderFactory returned $null. A provider instance is required for contract tests.'
            }

            $script:Credential = [PSCredential]::new(
                'contoso\syncadmin',
                (ConvertTo-SecureString -String 'P@ssw0rd!' -AsPlainText -Force)
            )

            $script:MockSession = [pscustomobject]@{
                Id = 1
            }
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
                    SyncCycleInProgress = $false
                }
            } -Force

            $script:Provider | Add-Member -MemberType ScriptMethod -Name RemoveRemoteSession -Value {
                param([object] $Session)
                $this.RemovedSession = $Session
            } -Force
        }

        It 'StartSyncCycle accepts ProviderInput and Credential auth session' {
            $providerInput = @{
                ComputerName = 'ad-sync1.corp.local'
                PolicyType = 'Delta'
            }
            $result = $script:Provider.StartSyncCycle($providerInput, $script:Credential)

            $result.Started | Should -BeTrue
            $script:Provider.LastComputerName | Should -Be 'ad-sync1.corp.local'
            $script:Provider.LastCredential | Should -Be $script:Credential
            $script:Provider.RemovedSession | Should -Be $script:MockSession
        }

        It 'GetSyncCycleState accepts ProviderInput and Credential auth session' {
            $providerInput = @{
                ComputerName = 'ad-sync1.corp.local'
            }
            $result = $script:Provider.GetSyncCycleState($providerInput, $script:Credential)

            $result.InProgress | Should -BeFalse
            $script:Provider.LastComputerName | Should -Be 'ad-sync1.corp.local'
            $script:Provider.LastCredential | Should -Be $script:Credential
            $script:Provider.RemovedSession | Should -Be $script:MockSession
        }
    }
}

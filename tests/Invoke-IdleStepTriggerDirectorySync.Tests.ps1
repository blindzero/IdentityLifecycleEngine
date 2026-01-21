Set-StrictMode -Version Latest

BeforeAll {
    . (Join-Path $PSScriptRoot '_testHelpers.ps1')
    Import-IdleTestModule
}

Describe 'Invoke-IdleStepTriggerDirectorySync (DirectorySync step)' {
    BeforeEach {
        # Mock directory sync provider
        $script:MockProvider = [pscustomobject]@{
            PSTypeName = 'Mock.DirectorySyncProvider'
            Name       = 'MockDirectorySyncProvider'
        }

        $script:MockProvider | Add-Member -MemberType ScriptMethod -Name GetCapabilities -Value {
            return @('IdLE.DirectorySync.Trigger', 'IdLE.DirectorySync.Status')
        } -Force

        $script:MockProvider | Add-Member -MemberType ScriptMethod -Name StartSyncCycle -Value {
            param(
                [Parameter(Mandatory)]
                [string] $PolicyType,

                [Parameter(Mandatory)]
                [object] $AuthSession
            )

            return [pscustomobject]@{
                Started = $true
                Message = "Sync cycle triggered with PolicyType: $PolicyType"
            }
        } -Force

        $script:MockProvider | Add-Member -MemberType ScriptMethod -Name GetSyncCycleState -Value {
            param(
                [Parameter(Mandatory)]
                [object] $AuthSession
            )

            # First call returns InProgress, subsequent calls return Idle
            if (-not $this.PSObject.Properties.Name -contains 'PollCount') {
                $this | Add-Member -NotePropertyName 'PollCount' -NotePropertyValue 0 -Force
            }
            $this.PollCount++

            $inProgress = $this.PollCount -le 1
            $state = if ($inProgress) { 'InProgress' } else { 'Idle' }

            return [pscustomobject]@{
                InProgress = $inProgress
                State      = $state
                Details    = @{}
            }
        } -Force

        # Mock auth session
        $script:MockAuthSession = [pscustomobject]@{ Name = 'MockAuthSession' }

        # Mock context
        $script:Context = [pscustomobject]@{
            PSTypeName = 'IdLE.ExecutionContext'
            Plan       = $null
            Providers  = @{ DirectorySync = $script:MockProvider }
            EventSink  = [pscustomobject]@{
                WriteEvent = { param($Type, $Message, $StepName, $Data) }
            }
        }

        $script:Context | Add-Member -MemberType ScriptMethod -Name AcquireAuthSession -Value {
            param(
                [Parameter(Mandatory)]
                [string] $Name,

                [Parameter()]
                [AllowNull()]
                [hashtable] $Options
            )

            return $script:MockAuthSession
        } -Force

        $script:StepTemplate = [pscustomobject]@{
            Name = 'Trigger sync'
            Type = 'IdLE.Step.TriggerDirectorySync'
            With = @{
                AuthSessionName = 'EntraConnect'
                PolicyType      = 'Delta'
                Provider        = 'DirectorySync'
            }
        }
    }

    Context 'Input validation' {
        It 'throws when With is missing' {
            $step = [pscustomobject]@{
                Name = 'Trigger sync'
                Type = 'IdLE.Step.TriggerDirectorySync'
            }

            $handler = 'IdLE.Steps.DirectorySync.EntraConnect\Invoke-IdleStepTriggerDirectorySync'
            { & $handler -Context $script:Context -Step $step } | Should -Throw -ErrorId * -ExpectedMessage '*With*hashtable*'
        }

        It 'throws when With.AuthSessionName is missing' {
            $step = $script:StepTemplate
            $step.With.Remove('AuthSessionName')

            $handler = 'IdLE.Steps.DirectorySync.EntraConnect\Invoke-IdleStepTriggerDirectorySync'
            { & $handler -Context $script:Context -Step $step } | Should -Throw -ErrorId * -ExpectedMessage '*AuthSessionName*'
        }

        It 'throws when With.PolicyType is missing' {
            $step = $script:StepTemplate
            $step.With.Remove('PolicyType')

            $handler = 'IdLE.Steps.DirectorySync.EntraConnect\Invoke-IdleStepTriggerDirectorySync'
            { & $handler -Context $script:Context -Step $step } | Should -Throw -ErrorId * -ExpectedMessage '*PolicyType*'
        }

        It 'throws when With.PolicyType is invalid' {
            $step = $script:StepTemplate
            $step.With.PolicyType = 'Invalid'

            $handler = 'IdLE.Steps.DirectorySync.EntraConnect\Invoke-IdleStepTriggerDirectorySync'
            { & $handler -Context $script:Context -Step $step } | Should -Throw -ErrorId * -ExpectedMessage '*PolicyType*'
        }

        It 'accepts Delta as PolicyType' {
            $step = $script:StepTemplate
            $step.With.PolicyType = 'Delta'

            $handler = 'IdLE.Steps.DirectorySync.EntraConnect\Invoke-IdleStepTriggerDirectorySync'
            $result = & $handler -Context $script:Context -Step $step

            $result.Status | Should -Be 'Completed'
        }

        It 'accepts Initial as PolicyType' {
            $step = $script:StepTemplate
            $step.With.PolicyType = 'Initial'

            $handler = 'IdLE.Steps.DirectorySync.EntraConnect\Invoke-IdleStepTriggerDirectorySync'
            $result = & $handler -Context $script:Context -Step $step

            $result.Status | Should -Be 'Completed'
        }

        It 'uses default provider alias when not specified' {
            $step = $script:StepTemplate
            $step.With.Remove('Provider')

            $handler = 'IdLE.Steps.DirectorySync.EntraConnect\Invoke-IdleStepTriggerDirectorySync'
            $result = & $handler -Context $script:Context -Step $step

            $result.Status | Should -Be 'Completed'
        }

        It 'throws when TimeoutSeconds is invalid' {
            $step = $script:StepTemplate
            $step.With.TimeoutSeconds = -1

            $handler = 'IdLE.Steps.DirectorySync.EntraConnect\Invoke-IdleStepTriggerDirectorySync'
            { & $handler -Context $script:Context -Step $step } | Should -Throw -ErrorId * -ExpectedMessage '*TimeoutSeconds*'
        }

        It 'throws when PollIntervalSeconds is invalid' {
            $step = $script:StepTemplate
            $step.With.PollIntervalSeconds = 0

            $handler = 'IdLE.Steps.DirectorySync.EntraConnect\Invoke-IdleStepTriggerDirectorySync'
            { & $handler -Context $script:Context -Step $step } | Should -Throw -ErrorId * -ExpectedMessage '*PollIntervalSeconds*'
        }
    }

    Context 'Trigger without wait' {
        It 'triggers sync cycle and completes immediately' {
            $step = $script:StepTemplate
            $step.With.Wait = $false

            $handler = 'IdLE.Steps.DirectorySync.EntraConnect\Invoke-IdleStepTriggerDirectorySync'
            $result = & $handler -Context $script:Context -Step $step

            $result.Status | Should -Be 'Completed'
            $result.Changed | Should -BeTrue
            $result.Error | Should -BeNullOrEmpty
        }

        It 'defaults to not waiting when Wait is not specified' {
            $step = $script:StepTemplate

            $handler = 'IdLE.Steps.DirectorySync.EntraConnect\Invoke-IdleStepTriggerDirectorySync'
            $result = & $handler -Context $script:Context -Step $step

            $result.Status | Should -Be 'Completed'
        }
    }

    Context 'Trigger with wait' {
        It 'triggers and waits for completion' {
            $step = $script:StepTemplate
            $step.With.Wait = $true
            $step.With.PollIntervalSeconds = 1

            $handler = 'IdLE.Steps.DirectorySync.EntraConnect\Invoke-IdleStepTriggerDirectorySync'
            $result = & $handler -Context $script:Context -Step $step

            $result.Status | Should -Be 'Completed'
            $result.Changed | Should -BeTrue
        }

        It 'throws timeout error when sync does not complete in time' {
            # Mock provider that never completes
            $script:MockProvider | Add-Member -MemberType ScriptMethod -Name GetSyncCycleState -Value {
                param([object] $AuthSession)
                return [pscustomobject]@{
                    InProgress = $true
                    State      = 'InProgress'
                    Details    = @{}
                }
            } -Force

            $step = $script:StepTemplate
            $step.With.Wait = $true
            $step.With.TimeoutSeconds = 2
            $step.With.PollIntervalSeconds = 1

            $handler = 'IdLE.Steps.DirectorySync.EntraConnect\Invoke-IdleStepTriggerDirectorySync'
            { & $handler -Context $script:Context -Step $step } | Should -Throw -ErrorId * -ExpectedMessage '*Timeout*'
        }

        It 'polls provider state multiple times' {
            $pollCalls = 0
            $script:MockProvider | Add-Member -MemberType ScriptMethod -Name GetSyncCycleState -Value {
                param([object] $AuthSession)
                $script:pollCalls++
                $inProgress = $script:pollCalls -le 2
                return [pscustomobject]@{
                    InProgress = $inProgress
                    State      = if ($inProgress) { 'InProgress' } else { 'Idle' }
                    Details    = @{}
                }
            } -Force

            $step = $script:StepTemplate
            $step.With.Wait = $true
            $step.With.PollIntervalSeconds = 1

            $handler = 'IdLE.Steps.DirectorySync.EntraConnect\Invoke-IdleStepTriggerDirectorySync'
            $result = & $handler -Context $script:Context -Step $step

            $script:pollCalls | Should -BeGreaterThan 1
        }
    }

    Context 'Provider interaction' {
        It 'throws when provider is missing' {
            $script:Context.Providers.Clear()

            $handler = 'IdLE.Steps.DirectorySync.EntraConnect\Invoke-IdleStepTriggerDirectorySync'
            { & $handler -Context $script:Context -Step $script:StepTemplate } | Should -Throw -ErrorId * -ExpectedMessage '*Provider*'
        }

        It 'throws when provider does not implement StartSyncCycle' {
            $badProvider = [pscustomobject]@{ Name = 'BadProvider' }
            $script:Context.Providers['DirectorySync'] = $badProvider

            $handler = 'IdLE.Steps.DirectorySync.EntraConnect\Invoke-IdleStepTriggerDirectorySync'
            { & $handler -Context $script:Context -Step $script:StepTemplate } | Should -Throw -ErrorId * -ExpectedMessage '*StartSyncCycle*'
        }
    }

    Context 'Event emission' {
        It 'emits DirectorySyncTriggered event' {
            $events = @()
            $script:Context.EventSink = [pscustomobject]@{
                WriteEvent = {
                    param($Type, $Message, $StepName, $Data)
                    $script:events += @{ Type = $Type; Message = $Message; StepName = $StepName; Data = $Data }
                }
            }

            $handler = 'IdLE.Steps.DirectorySync.EntraConnect\Invoke-IdleStepTriggerDirectorySync'
            $null = & $handler -Context $script:Context -Step $script:StepTemplate

            $events.Type | Should -Contain 'DirectorySyncTriggered'
        }

        It 'emits DirectorySyncCompleted event' {
            $events = @()
            $script:Context.EventSink = [pscustomobject]@{
                WriteEvent = {
                    param($Type, $Message, $StepName, $Data)
                    $script:events += @{ Type = $Type; Message = $Message; StepName = $StepName; Data = $Data }
                }
            }

            $handler = 'IdLE.Steps.DirectorySync.EntraConnect\Invoke-IdleStepTriggerDirectorySync'
            $null = & $handler -Context $script:Context -Step $script:StepTemplate

            $events.Type | Should -Contain 'DirectorySyncCompleted'
        }

        It 'emits DirectorySyncWaiting event when waiting' {
            $events = @()
            $script:Context.EventSink = [pscustomobject]@{
                WriteEvent = {
                    param($Type, $Message, $StepName, $Data)
                    $script:events += @{ Type = $Type; Message = $Message; StepName = $StepName; Data = $Data }
                }
            }

            $step = $script:StepTemplate
            $step.With.Wait = $true
            $step.With.PollIntervalSeconds = 1

            $handler = 'IdLE.Steps.DirectorySync.EntraConnect\Invoke-IdleStepTriggerDirectorySync'
            $null = & $handler -Context $script:Context -Step $step

            $events.Type | Should -Contain 'DirectorySyncWaiting'
        }
    }
}

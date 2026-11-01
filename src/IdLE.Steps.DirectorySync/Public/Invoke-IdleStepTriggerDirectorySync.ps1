function Invoke-IdleStepTriggerDirectorySync {
    <#
    .SYNOPSIS
    Triggers a directory sync cycle and optionally waits for completion.

    .DESCRIPTION
    This is a provider-agnostic step. The engine passes the provider resolved from With.Provider
    (default 'DirectorySync') as -Provider. The provider implements:
    - StartSyncCycle(PolicyType, ComputerName, AuthSession)
    - GetSyncCycleState(ComputerName, AuthSession)

    The step is designed for remote execution and requires an elevated auth session
    provided by the host's AuthSessionBroker.

    Authentication is handled by the engine: With.AuthSessionName (optional) and With.AuthSessionOptions
    select the session; without AuthSessionName the broker is asked for a default session.
    ComputerName and PolicyType are provider-specific inputs and are validated by the selected provider.

    .PARAMETER Context
    Execution context created by IdLE.Core.

    .PARAMETER With
    Validated With hashtable:
    - ComputerName (optional, string): provider-specific target server input
    - PolicyType (optional, string): provider-specific policy input
    - Wait (optional, bool): wait for cycle completion, defaults to $false
    - TimeoutSeconds (optional, int): wait timeout, defaults to 600
    - PollIntervalSeconds (optional, int): poll interval, defaults to 10

    .PARAMETER Provider
    Provider handle created by the engine (see docs/extend/steps.md).

    .PARAMETER Step
    Step metadata (Name, Type); the name is used for events.

    .OUTPUTS
    System.Collections.Hashtable (Changed)

    .EXAMPLE
    $step = @{
        Name = 'Trigger directory sync'
        Type = 'IdLE.Step.TriggerDirectorySync'
        With = @{
            AuthSessionName = 'DirectorySync'
            ComputerName = 'ad-sync1.corp.local'
            PolicyType = 'Delta'
            Wait = $true
        }
    }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Context,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable] $With,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Provider,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Step
    )

    $policyType = if ($With.ContainsKey('PolicyType')) { [string]$With.PolicyType } else { $null }
    $computerName = if ($With.ContainsKey('ComputerName')) { [string]$With.ComputerName } else { $null }

    # Defaults come from the step metadata (Wait = $false, TimeoutSeconds = 600, PollIntervalSeconds = 10).
    $wait = [bool]$With.Wait
    $timeoutSeconds = [int]$With.TimeoutSeconds
    $pollIntervalSeconds = [int]$With.PollIntervalSeconds

    # Validate timeout and poll interval
    if ($timeoutSeconds -le 0) {
        throw "TriggerDirectorySync: With.TimeoutSeconds must be greater than 0. Got: $timeoutSeconds"
    }
    if ($pollIntervalSeconds -le 0) {
        throw "TriggerDirectorySync: With.PollIntervalSeconds must be greater than 0. Got: $pollIntervalSeconds"
    }

    $stepName = [string]$Step.Name

    try {
        # Trigger sync cycle
        $policyTypeText = [string]$policyType
        $triggerMessage = if ([string]::IsNullOrWhiteSpace($policyTypeText)) {
            'Triggering directory sync cycle'
        }
        else {
            "Triggering $policyTypeText sync cycle"
        }

        $Context.EventSink.WriteEvent('IdLE.Step.DirectorySync.Triggered', $triggerMessage, $stepName, @{
                PolicyType = $policyType
                ComputerName = $computerName
            })

        $startResult = $Provider.Invoke('StartSyncCycle', @($policyType, $computerName))

        $changed = $false
        if ($null -ne $startResult -and ($startResult.PSObject.Properties.Name -contains 'Started')) {
            $changed = [bool]$startResult.Started
        }

        # If wait is requested, poll until complete or timeout
        if ($wait) {
            $Context.EventSink.WriteEvent('IdLE.Step.DirectorySync.Waiting', "Waiting for sync cycle to complete (timeout: ${timeoutSeconds}s)", $stepName, @{
                    TimeoutSeconds = $timeoutSeconds
                    PollIntervalSeconds = $pollIntervalSeconds
                })

            $startTime = [datetime]::UtcNow
            $attempt = 0

            while ($true) {
                $attempt++
                $elapsed = ([datetime]::UtcNow - $startTime).TotalSeconds

                if ($elapsed -ge $timeoutSeconds) {
                    # Timeout reached - fail
                    $stateResult = $Provider.Invoke('GetSyncCycleState', @($computerName))

                    $lastState = if ($null -ne $stateResult) { $stateResult.State } else { 'Unknown' }

                    $Context.EventSink.WriteEvent('IdLE.Step.DirectorySync.Failed', "Sync cycle wait timeout after ${timeoutSeconds}s", $stepName, @{
                            TimeoutSeconds = $timeoutSeconds
                            ElapsedSeconds = [int]$elapsed
                            LastKnownState = $lastState
                        }, 'Error')

                    throw "TriggerDirectorySync: Timeout waiting for sync cycle to complete after ${timeoutSeconds}s. Last known state: $lastState"
                }

                # Poll state
                $stateResult = $Provider.Invoke('GetSyncCycleState', @($computerName))

                $inProgress = $true
                if ($null -ne $stateResult -and ($stateResult.PSObject.Properties.Name -contains 'InProgress')) {
                    $inProgress = [bool]$stateResult.InProgress
                }

                $currentState = if ($null -ne $stateResult) { $stateResult.State } else { 'Unknown' }

                $Context.EventSink.WriteEvent('IdLE.Step.DirectorySync.Polled', "Poll attempt $attempt - State: $currentState", $stepName, @{
                        Attempt = $attempt
                        State = $currentState
                        InProgress = $inProgress
                        ElapsedSeconds = [int]$elapsed
                    })

                if (-not $inProgress) {
                    # Sync cycle completed
                    $Context.EventSink.WriteEvent('IdLE.Step.DirectorySync.Completed', "Sync cycle completed", $stepName, @{
                            Attempts = $attempt
                            ElapsedSeconds = [int]$elapsed
                        })
                    break
                }

                # Wait before next poll
                Start-Sleep -Seconds $pollIntervalSeconds
            }
        }
        else {
            # Not waiting - sync triggered successfully
            $Context.EventSink.WriteEvent('IdLE.Step.DirectorySync.Completed', "Sync cycle triggered (not waiting)", $stepName, @{
                    PolicyType = $policyType
                })
        }

        return @{ Changed = $changed }
    }
    catch {
        $Context.EventSink.WriteEvent('IdLE.Step.DirectorySync.Failed', "Failed to trigger or wait for sync cycle: $_", $stepName, @{
                Error = $_.Exception.Message
            }, 'Error')
        throw
    }
}

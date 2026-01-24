function Invoke-IdleStepTriggerDirectorySync {
    <#
    .SYNOPSIS
    Triggers a directory sync cycle and optionally waits for completion.

    .DESCRIPTION
    This is a provider-agnostic step. The host must supply a provider instance via
    Context.Providers[<ProviderAlias>] that implements:
    - StartSyncCycle(PolicyType, AuthSession)
    - GetSyncCycleState(AuthSession)

    The step is designed for remote execution and requires an elevated auth session
    provided by the host's AuthSessionBroker.

    Authentication:
    - With.AuthSessionName (required): routing key for AuthSessionBroker
    - With.AuthSessionOptions (optional, hashtable): forwarded to broker for session selection
    - ScriptBlocks in AuthSessionOptions are rejected (security boundary)

    .PARAMETER Context
    Execution context created by IdLE.Core.

    .PARAMETER Step
    Normalized step object from the plan. Must contain a 'With' hashtable with keys:
    - AuthSessionName (required, string): auth session name for broker
    - PolicyType (required, string): 'Delta' or 'Initial' (case-insensitive)
    - Provider (optional, string): provider alias, defaults to 'DirectorySync'
    - Wait (optional, bool): wait for cycle completion, defaults to $false
    - TimeoutSeconds (optional, int): wait timeout, defaults to 600
    - PollIntervalSeconds (optional, int): poll interval, defaults to 10
    - AuthSessionOptions (optional, hashtable): forwarded to broker

    .OUTPUTS
    PSCustomObject (PSTypeName: IdLE.StepResult)

    .EXAMPLE
    $step = @{
        Name = 'Trigger directory sync'
        Type = 'IdLE.Step.TriggerDirectorySync'
        With = @{
            AuthSessionName = 'DirectorySync'
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
        [object] $Step
    )

    $with = $Step.With
    if ($null -eq $with -or -not ($with -is [hashtable])) {
        throw "TriggerDirectorySync requires 'With' to be a hashtable."
    }

    # Validate required inputs
    if (-not $with.ContainsKey('AuthSessionName')) {
        throw "TriggerDirectorySync requires With.AuthSessionName."
    }

    if (-not $with.ContainsKey('PolicyType')) {
        throw "TriggerDirectorySync requires With.PolicyType."
    }

    $policyType = [string]$with.PolicyType
    if ($policyType -notin @('Delta', 'Initial')) {
        throw "TriggerDirectorySync: With.PolicyType must be 'Delta' or 'Initial' (case-insensitive). Got: $policyType"
    }

    # Optional inputs with defaults
    $providerAlias = if ($with.ContainsKey('Provider')) { [string]$with.Provider } else { 'DirectorySync' }
    $wait = if ($with.ContainsKey('Wait')) { [bool]$with.Wait } else { $false }
    $timeoutSeconds = if ($with.ContainsKey('TimeoutSeconds')) { [int]$with.TimeoutSeconds } else { 600 }
    $pollIntervalSeconds = if ($with.ContainsKey('PollIntervalSeconds')) { [int]$with.PollIntervalSeconds } else { 10 }

    # Validate timeout and poll interval
    if ($timeoutSeconds -le 0) {
        throw "TriggerDirectorySync: With.TimeoutSeconds must be greater than 0. Got: $timeoutSeconds"
    }
    if ($pollIntervalSeconds -le 0) {
        throw "TriggerDirectorySync: With.PollIntervalSeconds must be greater than 0. Got: $pollIntervalSeconds"
    }

    # Validate provider exists
    if (-not ($Context.PSObject.Properties.Name -contains 'Providers')) {
        throw "Context does not contain a Providers hashtable."
    }
    if ($null -eq $Context.Providers -or -not ($Context.Providers -is [hashtable])) {
        throw "Context.Providers must be a hashtable."
    }
    if (-not $Context.Providers.ContainsKey($providerAlias)) {
        throw "Provider '$providerAlias' was not supplied by the host."
    }

    $stepName = if ($Step.PSObject.Properties.Name -contains 'Name') { [string]$Step.Name } else { 'TriggerDirectorySync' }

    try {
        # Trigger sync cycle
        $Context.EventSink.WriteEvent('DirectorySyncTriggered', "Triggering $policyType sync cycle", $stepName, @{
                PolicyType = $policyType
            })

        $startResult = Invoke-IdleProviderMethod `
            -Context $Context `
            -With $with `
            -ProviderAlias $providerAlias `
            -MethodName 'StartSyncCycle' `
            -MethodArguments @($policyType)

        $changed = $false
        if ($null -ne $startResult -and ($startResult.PSObject.Properties.Name -contains 'Started')) {
            $changed = [bool]$startResult.Started
        }

        # If wait is requested, poll until complete or timeout
        if ($wait) {
            $Context.EventSink.WriteEvent('DirectorySyncWaiting', "Waiting for sync cycle to complete (timeout: ${timeoutSeconds}s)", $stepName, @{
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
                    $stateResult = Invoke-IdleProviderMethod `
                        -Context $Context `
                        -With $with `
                        -ProviderAlias $providerAlias `
                        -MethodName 'GetSyncCycleState' `
                        -MethodArguments @()

                    $lastState = if ($null -ne $stateResult) { $stateResult.State } else { 'Unknown' }

                    $Context.EventSink.WriteEvent('DirectorySyncFailed', "Sync cycle wait timeout after ${timeoutSeconds}s", $stepName, @{
                            TimeoutSeconds = $timeoutSeconds
                            ElapsedSeconds = [int]$elapsed
                            LastKnownState = $lastState
                        })

                    throw "TriggerDirectorySync: Timeout waiting for sync cycle to complete after ${timeoutSeconds}s. Last known state: $lastState"
                }

                # Poll state
                $stateResult = Invoke-IdleProviderMethod `
                    -Context $Context `
                    -With $with `
                    -ProviderAlias $providerAlias `
                    -MethodName 'GetSyncCycleState' `
                    -MethodArguments @()

                $inProgress = $true
                if ($null -ne $stateResult -and ($stateResult.PSObject.Properties.Name -contains 'InProgress')) {
                    $inProgress = [bool]$stateResult.InProgress
                }

                $currentState = if ($null -ne $stateResult) { $stateResult.State } else { 'Unknown' }

                $Context.EventSink.WriteEvent('DirectorySyncPoll', "Poll attempt $attempt - State: $currentState", $stepName, @{
                        Attempt = $attempt
                        State = $currentState
                        InProgress = $inProgress
                        ElapsedSeconds = [int]$elapsed
                    })

                if (-not $inProgress) {
                    # Sync cycle completed
                    $Context.EventSink.WriteEvent('DirectorySyncCompleted', "Sync cycle completed", $stepName, @{
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
            $Context.EventSink.WriteEvent('DirectorySyncCompleted', "Sync cycle triggered (not waiting)", $stepName, @{
                    PolicyType = $policyType
                })
        }

        return [pscustomobject]@{
            PSTypeName = 'IdLE.StepResult'
            Name       = $stepName
            Type       = [string]$Step.Type
            Status     = 'Completed'
            Changed    = $changed
            Error      = $null
        }
    }
    catch {
        $Context.EventSink.WriteEvent('DirectorySyncFailed', "Failed to trigger or wait for sync cycle: $_", $stepName, @{
                Error = $_.Exception.Message
            })
        throw
    }
}

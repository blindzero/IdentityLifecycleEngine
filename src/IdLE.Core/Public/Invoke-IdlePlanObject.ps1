function Invoke-IdlePlanObject {
    <#
    .SYNOPSIS
    Executes an IdLE plan (skeleton).

    .DESCRIPTION
    Executes a plan deterministically and emits structured events.
    Executes steps via a registry mapping Step.Type to PowerShell functions.

    .PARAMETER Plan
    Plan object created by New-IdlePlanObject.

    .PARAMETER Providers
    Provider registry/collection (used for StepRegistry in this increment; passed through for future steps).

    .PARAMETER EventSink
    Optional external event sink provided by the host.

    .OUTPUTS
    PSCustomObject (PSTypeName: IdLE.ExecutionResult)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Plan,

        [Parameter()]
        [AllowNull()]
        [hashtable] $Providers,

        [Parameter()]
        [AllowNull()]
        [object] $EventSink
    )

    $planProps = @($Plan.PSObject.Properties.Name)

    # The engine rejects ScriptBlocks in the plan and providers to avoid accidental code execution.
    Assert-IdleNoScriptBlock -InputObject $Plan -Path 'Plan'
    Assert-IdleNoScriptBlock -InputObject $Providers -Path 'Providers'

    $events = [System.Collections.Generic.List[object]]::new()

    $corr  = [string]$Plan.CorrelationId
    $actor = if ($planProps -contains 'Actor') { [string]$Plan.Actor } else { $null }

    # Create the engine-managed event sink object used by both the engine and steps.
    # This keeps event shape deterministic and isolates host-provided sinks behind a single contract.
    $engineEventSink = New-IdleEventSink -CorrelationId $corr -Actor $actor -ExternalEventSink $EventSink -EventBuffer $events

    # Resolve step types to PowerShell functions via a registry.
    #
    # IMPORTANT:
    # - The host MAY provide a StepRegistry, but it is optional.
    # - Built-in steps must remain discoverable without requiring the host to wire a registry.
    # - Get-IdleStepRegistry merges the host registry (if provided) with built-in handlers (if available).
    $stepRegistry = Get-IdleStepRegistry -Providers $Providers

    $context = [pscustomobject]@{
        PSTypeName = 'IdLE.ExecutionContext'
        Plan       = $Plan
        Providers  = $Providers

        # Object-based, stable eventing contract.
        # Steps and the engine call: $Context.EventSink.WriteEvent(...)
        EventSink  = $engineEventSink
    }

    # Execution retry policy (safe-by-default):
    # - Only retry errors explicitly marked transient by trusted code paths (Exception.Data['Idle.IsTransient'] = $true).
    # - Fail fast for all other errors.
    # NOTE: This is currently engine-owned and not configurable via plan/workflow to keep the surface small in this increment.
    $retryPolicy = @{
        MaxAttempts             = 3
        InitialDelayMilliseconds = 250
        BackoffFactor           = 2.0
        MaxDelayMilliseconds    = 5000
        JitterRatio             = 0.2
    }

    # Emit run start event.
    $context.EventSink.WriteEvent('RunStarted', 'Plan execution started.', $null, @{
        LifecycleEvent = [string]$Plan.LifecycleEvent
        WorkflowName   = if ($planProps -contains 'WorkflowName') {
            [string]$Plan.WorkflowName
        } else {
            $null
        }
        StepCount      = @($Plan.Steps).Count
    })

    $stepResults = @()
    $failed = $false

    $i = 0
    foreach ($step in @($Plan.Steps)) {
        $stepName = if ($step.PSObject.Properties.Name -contains 'Name') { [string]$step.Name } else { "Step[$i]" }
        $stepType = if ($step.PSObject.Properties.Name -contains 'Type' -and $null -ne $step.Type) {
            ([string]$step.Type).Trim()
        } else {
            $null
        }

        # Step applicability is evaluated during planning (New-IdlePlanObject).
        # At execution time we only respect the planned status.
        if ($step.PSObject.Properties.Name -contains 'When') {
            throw [System.ArgumentException]::new(
                "Plan step '$stepName' still contains legacy key 'When'. This has been renamed to 'Condition'. Please rebuild the plan with an updated workflow definition.",
                'Plan'
            )
        }

        if ($step.PSObject.Properties.Name -contains 'Status' -and [string]$step.Status -eq 'NotApplicable') {

            # Synthetic step result: the step was not executed because it was deemed not applicable at plan time.
            $stepResults += [pscustomobject]@{
                PSTypeName = 'IdLE.StepResult'
                Name       = $stepName
                Type       = $stepType
                Status     = 'NotApplicable'
                Error      = $null
                Attempts   = 0
            }

            $context.EventSink.WriteEvent('StepNotApplicable', "Step '$stepName' not applicable (condition not met).", $stepName, @{
                StepType = $stepType
                Index    = $i
            })

            $i++
            continue
        }

        $context.EventSink.WriteEvent('StepStarted', "Step '$stepName' started.", $stepName, @{
            StepType = $stepType
            Index    = $i
        })

        try {
            # Resolve implementation handler for this step type.
            # Handler must be a function name (string).
            if ($null -eq $stepType -or [string]::IsNullOrWhiteSpace($stepType)) {
                throw [System.ArgumentException]::new("Step '$stepName' is missing a valid Type.", 'Plan')
            }

            if ($null -eq $stepRegistry -or -not ($stepRegistry.ContainsKey($stepType))) {
                throw [System.ArgumentException]::new("No step handler registered for type '$stepType'.", 'Providers')
            }

            $handlerName = [string]$stepRegistry[$stepType]
            if ([string]::IsNullOrWhiteSpace($handlerName)) {
                throw [System.ArgumentException]::new("Step handler for type '$stepType' is not a valid function name.", 'Providers')
            }

            # Execute the step via handler using safe retries for transient failures.
            # Retries are only performed if trusted code marks the exception as transient.
            $operationName = "Step '$stepName' ($stepType)"
            $retrySeed = "Plan:$corr|Step:$stepName|Type:$stepType"

            $retryResult = Invoke-IdleWithRetry -Operation {
                & $handlerName -Context $context -Step $step
            } -MaxAttempts $retryPolicy.MaxAttempts `
              -InitialDelayMilliseconds $retryPolicy.InitialDelayMilliseconds `
              -BackoffFactor $retryPolicy.BackoffFactor `
              -MaxDelayMilliseconds $retryPolicy.MaxDelayMilliseconds `
              -JitterRatio $retryPolicy.JitterRatio `
              -EventSink $context.EventSink `
              -StepName $stepName `
              -OperationName $operationName `
              -DeterministicSeed $retrySeed

            $result   = $retryResult.Value
            $attempts = [int]$retryResult.Attempts

            # Normalize result shape (minimal contract).
            $stepResults += [pscustomobject]@{
                PSTypeName = 'IdLE.StepResult'
                Name       = $stepName
                Type       = $stepType
                Status     = if ($null -ne $result -and $result.PSObject.Properties.Name -contains 'Status') { [string]$result.Status } else { 'Completed' }
                Error      = if ($null -ne $result -and $result.PSObject.Properties.Name -contains 'Error')  { $result.Error } else { $null }
                Attempts   = $attempts
            }

            $context.EventSink.WriteEvent('StepCompleted', "Step '$stepName' completed.", $stepName, @{
                StepType  = $stepType
                Index     = $i
                Attempts  = $attempts
            })
        }
        catch {
            $failed = $true
            $err = $_

            # We cannot reliably know the number of attempts on failure without wrapping errors.
            # For this increment, we keep the output stable and report a minimum of 1 attempt.
            $stepResults += [pscustomobject]@{
                PSTypeName = 'IdLE.StepResult'
                Name       = $stepName
                Type       = $stepType
                Status     = 'Failed'
                Error      = $err.Exception.Message
                Attempts   = 1
            }

            $context.EventSink.WriteEvent('StepFailed', "Step '$stepName' failed.", $stepName, @{
                StepType = $stepType
                Index    = $i
                Error    = $err.Exception.Message
            })

            # Fail-fast in this increment.
            break
        }

        $i++
    }

    $runStatus = if ($failed) { 'Failed' } else { 'Completed' }

    $context.EventSink.WriteEvent('RunCompleted', "Plan execution finished (status: $runStatus).", $null, @{
        Status    = $runStatus
        StepCount = @($Plan.Steps).Count
    })

    return [pscustomobject]@{
        PSTypeName    = 'IdLE.ExecutionResult'
        Status        = $runStatus
        CorrelationId = $corr
        Actor         = $actor
        Steps         = $stepResults
        Events        = $events
        Providers     = $Providers
    }
}

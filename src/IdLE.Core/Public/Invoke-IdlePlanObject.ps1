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
    # This decouples workflow "Type" strings from actual implementation functions.
    $stepRegistry = $null
    if ($null -ne $Providers -and $Providers.ContainsKey('StepRegistry')) {
        $stepRegistry = $Providers.StepRegistry
    }

    $context = [pscustomobject]@{
        PSTypeName    = 'IdLE.ExecutionContext'
        Plan          = $Plan
        Providers     = $Providers

        # Object-based, stable eventing contract.
        # Steps and the engine call: $Context.EventSink.WriteEvent(...)
        EventSink     = $engineEventSink
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

            # Execute the step via handler.
            $result = & $handlerName -Context $context -Step $step

            # Normalize result shape (minimal contract).
            $stepResults += [pscustomobject]@{
                PSTypeName = 'IdLE.StepResult'
                Name       = $stepName
                Type       = $stepType
                Status     = if ($null -ne $result -and $result.PSObject.Properties.Name -contains 'Status') { [string]$result.Status } else { 'Completed' }
                Error      = if ($null -ne $result -and $result.PSObject.Properties.Name -contains 'Error')  { $result.Error } else { $null }
            }

            $context.EventSink.WriteEvent('StepCompleted', "Step '$stepName' completed.", $stepName, @{
                StepType = $stepType
                Index    = $i
            })
        }
        catch {
            $failed = $true
            $err = $_

            $stepResults += [pscustomobject]@{
                PSTypeName = 'IdLE.StepResult'
                Name       = $stepName
                Type       = $stepType
                Status     = 'Failed'
                Error      = $err.Exception.Message
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

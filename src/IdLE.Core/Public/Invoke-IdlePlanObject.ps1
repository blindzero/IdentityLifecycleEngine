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
    Optional external event sink for streaming. Must be an object with a WriteEvent(event) method.

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
        [object] $Providers,

        [Parameter()]
        [AllowNull()]
        [object] $EventSink
    )

    # Validate minimal plan shape. Avoid hard typing to keep cross-module compatibility.
    $planProps = $Plan.PSObject.Properties.Name
    foreach ($required in @('CorrelationId', 'LifecycleEvent', 'Steps')) {
        if ($planProps -notcontains $required) {
            throw [System.ArgumentException]::new("Plan object must contain property '$required'.", 'Plan')
        }
    }

    # Secure default: treat host-provided extension points as privileged inputs.
    # The engine rejects ScriptBlocks in the plan and providers to avoid accidental code execution.
    Assert-IdleNoScriptBlock -InputObject $Plan -Path 'Plan'
    Assert-IdleNoScriptBlock -InputObject $Providers -Path 'Providers'

    $events = [System.Collections.Generic.List[object]]::new()

    $corr = [string]$Plan.CorrelationId
    $actor = if ($planProps -contains 'Actor') { [string]$Plan.Actor } else { $null }

    # Create the engine-managed event sink object used by both the engine and steps.
    # This keeps event shape deterministic and isolates host-provided sinks behind a single contract.
    $engineEventSink = New-IdleEventSink -CorrelationId $corr -Actor $actor -ExternalEventSink $EventSink -EventBuffer $events

    # Resolve step types to PowerShell functions via a registry.
    # This decouples workflow "Type" strings from actual implementation functions.
    $registry = Get-IdleStepRegistry -Providers $Providers

    # Provide a small execution context for steps.
    # Steps must not call engine-private functions directly; they only use the context.
    $context = [pscustomobject]@{
        PSTypeName    = 'IdLE.ExecutionContext'
        CorrelationId = $corr
        Actor         = $actor
        Plan          = $Plan
        Providers     = $Providers

        # Object-based, stable eventing contract.
        # Steps and the engine call: $Context.EventSink.WriteEvent(...)
        EventSink     = $engineEventSink
    }

    # Emit run start event.
    $context.EventSink.WriteEvent('RunStarted', 'Plan execution started.', $null, @{
        LifecycleEvent = [string]$Plan.LifecycleEvent
        WorkflowName = if ($planProps -contains 'WorkflowName') {
            [string]$Plan.WorkflowName
        } else {
            $null
        }
        StepCount = @($Plan.Steps).Count
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

        # Evaluate declarative When condition (data-only).
        if ($step.PSObject.Properties.Name -contains 'When' -and $null -ne $step.When) {
            $shouldRun = Test-IdleWhenCondition -When $step.When -Context $context
            if (-not $shouldRun) {
                $stepResults += [pscustomobject]@{
                    PSTypeName = 'IdLE.StepResult'
                    Name       = $stepName
                    Type       = $stepType
                    Status     = 'Skipped'
                    Error      = $null
                }

                $context.EventSink.WriteEvent('StepSkipped', "Step '$stepName' skipped (condition not met).", $stepName, @{
                    StepType = $stepType
                    Index    = $i
                })

                $i++
                continue
            }
        }

        $context.EventSink.WriteEvent('StepStarted', "Step '$stepName' started.", $stepName, @{
            StepType = $stepType
            Index    = $i
        })

        try {
            # Resolve implementation handler for this step type.
            # Handler must be a function name (string).
            $handler = Resolve-IdleStepHandler -StepType $stepType -Registry $registry
            if ($null -eq $handler) {
                throw [System.InvalidOperationException]::new("Step type '$stepType' is not registered.")
            }

            # Invoke the step plugin.
            $stepResult = & $handler -Context $context -Step $step

            $stepResults += $stepResult

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

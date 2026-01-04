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

    # Host may pass an external sink. If none is provided, we still buffer events internally.
    $engineEventSink = New-IdleEventSink -EventSink $EventSink -EventBuffer $events

    $failed = $false
    $stepResults = @()

    # In this increment, request fields are accessed defensively.
    $request = if ($planProps -contains 'Request') { $Plan.Request } else { $null }

    $corr = if ($null -ne $request -and @($request.PSObject.Properties.Name) -contains 'CorrelationId') {
        $request.CorrelationId
    }
    else {
        if ($planProps -contains 'CorrelationId') { $Plan.CorrelationId } else { $null }
    }

    $actor = if ($null -ne $request -and @($request.PSObject.Properties.Name) -contains 'Actor') {
        $request.Actor
    }
    else {
        if ($planProps -contains 'Actor') { $Plan.Actor } else { $null }
    }

    # StepRegistry is constructed via helper to ensure built-in steps and host-provided steps can co-exist.
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

    $context.EventSink.WriteEvent('RunStarted', "Plan execution started (correlationId: $corr).", $null, @{
        CorrelationId = $corr
        Actor         = $actor
        StepCount     = @($Plan.Steps).Count
    })

    $i = 0
    foreach ($step in $Plan.Steps) {

        if ($null -eq $step) {
            continue
        }

        $stepName = $step.Name
        $stepType = $step.Type
        $stepWith = if (@($step.PSObject.Properties.Name) -contains 'With') { $step.With } else { $null }

        # Conditions are evaluated before the step executes (if present).
        $stepCondition = if (@($step.PSObject.Properties.Name) -contains 'Condition') { $step.Condition } else { $null }
        if ($null -ne $stepCondition) {

            $isApplicable = Invoke-IdleConditionTest -Condition $stepCondition -Context $context

            if (-not $isApplicable) {
                $stepResults += [pscustomobject]@{
                    PSTypeName = 'IdLE.StepResult'
                    Name       = $stepName
                    Type       = $stepType
                    Status     = 'NotApplicable'
                    Attempts   = 1
                }

                $context.EventSink.WriteEvent('StepNotApplicable', "Step '$stepName' not applicable (condition not met).", $stepName, @{
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
            $impl = $stepRegistry.GetStep($stepType)

            $invokeParams = @{
                Context = $context
            }

            if ($null -ne $stepWith) {
                $invokeParams.With = $stepWith
            }

            $result = & $impl @invokeParams

            if ($null -eq $result) {
                # Steps should return a result, but to keep execution stable we normalize to Completed.
                $result = [pscustomobject]@{
                    PSTypeName = 'IdLE.StepResult'
                    Name       = $stepName
                    Type       = $stepType
                    Status     = 'Completed'
                    Attempts   = 1
                }
            }

            $stepResults += $result

            if ($result.Status -eq 'Failed') {
                $failed = $true

                $context.EventSink.WriteEvent('StepFailed', "Step '$stepName' failed.", $stepName, @{
                    StepType = $stepType
                    Index    = $i
                    Error    = $result.Error
                })

                # Fail-fast for this increment.
                break
            }

            $context.EventSink.WriteEvent('StepCompleted', "Step '$stepName' completed.", $stepName, @{
                StepType = $stepType
                Index    = $i
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

            # Fail-fast for this increment.
            break
        }

        $i++
    }

    $runStatus = if ($failed) { 'Failed' } else { 'Completed' }

    $context.EventSink.WriteEvent('RunCompleted', "Plan execution finished (status: $runStatus).", $null, @{
        Status    = $runStatus
        StepCount = @($Plan.Steps).Count
    })

    # Redact provider configuration/state at the output boundary (execution result).
    # We never mutate the original providers object; we return a redacted copy.
    $redactedProviders = if ($null -ne $Providers) {
        Copy-IdleRedactedObject -Value $Providers
    }
    else {
        $null
    }

    return [pscustomobject]@{
        PSTypeName    = 'IdLE.ExecutionResult'
        Status        = $runStatus
        CorrelationId = $corr
        Actor         = $actor
        Steps         = $stepResults
        Events        = $events
        Providers     = $redactedProviders
    }
}

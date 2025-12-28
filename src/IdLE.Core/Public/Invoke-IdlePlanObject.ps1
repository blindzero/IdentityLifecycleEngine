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
    Optional sink for event streaming. Can be a ScriptBlock or an object with a WriteEvent() method.

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

    $events = [System.Collections.Generic.List[object]]::new()

    $corr = [string]$Plan.CorrelationId
    $actor = if ($planProps -contains 'Actor') { [string]$Plan.Actor } else { $null }

    # Capture command references once to avoid scope/name resolution issues inside closures.
    $newIdleEventCmd   = Get-Command -Name 'New-IdleEvent'   -CommandType Function -ErrorAction Stop
    $writeIdleEventCmd = Get-Command -Name 'Write-IdleEvent' -CommandType Function -ErrorAction Stop

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

        # Expose a single event writer for steps.
        # The engine stays in control of event shape, sinks and buffering.
        WriteEvent    = {
            param(
                [Parameter(Mandatory)][string] $Type,
                [Parameter(Mandatory)][string] $Message,
                [Parameter()][AllowNull()][string] $StepName,
                [Parameter()][AllowNull()][hashtable] $Data
            )

            # Use captured command references to avoid scope/name resolution issues in step handlers.
            $evt = & $newIdleEventCmd -Type $Type -Message $Message -CorrelationId $corr -Actor $actor -StepName $StepName -Data $Data
            & $writeIdleEventCmd -Event $evt -EventSink $EventSink -EventBuffer $events
        }.GetNewClosure()
    }

    # Emit run start event.
    & $context.WriteEvent 'RunStarted' 'Plan execution started.' $null @{
        LifecycleEvent = [string]$Plan.LifecycleEvent
        WorkflowName = if ($planProps -contains 'WorkflowName') {
            [string]$Plan.WorkflowName
        } else {
            $null
        }
        StepCount = @($Plan.Steps).Count
    }

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

        & $context.WriteEvent 'StepStarted' "Step '$stepName' started." $stepName @{
            StepType = $stepType
            Index    = $i
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

                & $context.WriteEvent 'StepSkipped' "Step '$stepName' skipped (condition not met)." $stepName @{
                    StepType = $stepType
                    Index    = $i
                }

                $i++
                continue
            }
        }

        try {
            # Resolve implementation handler for this step type.
            # Handler can be:
            # - [scriptblock] : invoked as & $handler $context $step
            # - [string]      : function name invoked as & $handler -Context $context -Step $step
            $handler = Resolve-IdleStepHandler -StepType $stepType -Registry $registry
            if ($null -eq $handler) {
                throw [System.InvalidOperationException]::new("Step type '$stepType' is not registered.")
            }

            # Invoke the step plugin depending on handler type.
            if ($handler -is [scriptblock]) {
                $stepResult = & $handler $context $step
            }
            else {
                # handler is a function name (string)
                $stepResult = & $handler -Context $context -Step $step
            }

            $stepResults += $stepResult

            & $context.WriteEvent 'StepCompleted' "Step '$stepName' completed." $stepName @{
                StepType = $stepType
                Index    = $i
            }
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

            & $context.WriteEvent 'StepFailed' "Step '$stepName' failed." $stepName @{
                StepType = $stepType
                Index    = $i
                Error    = $err.Exception.Message
            }

            # Fail-fast in this increment.
            break
        }

        $i++
    }

    $runStatus = if ($failed) { 'Failed' } else { 'Completed' }

    & $context.WriteEvent 'RunCompleted' "Plan execution finished (status: $runStatus)." $null @{
        Status    = $runStatus
        StepCount = @($Plan.Steps).Count
    }

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

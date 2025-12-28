function Invoke-IdlePlanObject {
    <#
    .SYNOPSIS
    Executes an IdLE plan (skeleton).

    .DESCRIPTION
    Executes a plan deterministically and emits structured events.
    This increment does NOT execute real step plugins yet. It only simulates step execution.

    .PARAMETER Plan
    Plan object created by New-IdlePlanObject.

    .PARAMETER Providers
    Provider registry/collection (not used in this increment; passed through for future steps).

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

    # Emit run start event.
    Write-IdleEvent -Event (New-IdleEvent -Type 'RunStarted' -Message 'Plan execution started.' -CorrelationId $corr -Actor $actor -Data @{
        LifecycleEvent = [string]$Plan.LifecycleEvent
        WorkflowName   = if ($planProps -contains 'WorkflowName') { [string]$Plan.WorkflowName } else { $null }
        StepCount      = @($Plan.Steps).Count
    }) -EventSink $EventSink -EventBuffer $events

    $stepResults = @()
    $failed = $false

    $i = 0
    foreach ($step in @($Plan.Steps)) {
        $stepName = if ($step.PSObject.Properties.Name -contains 'Name') { [string]$step.Name } else { "Step[$i]" }
        $stepType = if ($step.PSObject.Properties.Name -contains 'Type') { [string]$step.Type } else { $null }

        Write-IdleEvent -Event (New-IdleEvent -Type 'StepStarted' -Message "Step '$stepName' started." -CorrelationId $corr -Actor $actor -StepName $stepName -Data @{
            StepType = $stepType
            Index    = $i
        }) -EventSink $EventSink -EventBuffer $events

        try {
            # Skeleton behavior: no real execution yet.
            # We treat all steps as "Skipped/NotImplemented" to keep deterministic behavior.
            $status = 'NotImplemented'

            $stepResults += [pscustomobject]@{
                PSTypeName = 'IdLE.StepResult'
                Name       = $stepName
                Type       = $stepType
                Status     = $status
                Error      = $null
            }

            Write-IdleEvent -Event (New-IdleEvent -Type 'StepCompleted' -Message "Step '$stepName' completed (status: $status)." -CorrelationId $corr -Actor $actor -StepName $stepName -Data @{
                StepType = $stepType
                Status   = $status
                Index    = $i
            }) -EventSink $EventSink -EventBuffer $events
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

            Write-IdleEvent -Event (New-IdleEvent -Type 'StepFailed' -Message "Step '$stepName' failed." -CorrelationId $corr -Actor $actor -StepName $stepName -Data @{
                StepType  = $stepType
                Index     = $i
                Error     = $err.Exception.Message
            }) -EventSink $EventSink -EventBuffer $events

            # Fail-fast in this increment.
            break
        }

        $i++
    }

    $runStatus = if ($failed) { 'Failed' } else { 'Completed' }

    Write-IdleEvent -Event (New-IdleEvent -Type 'RunCompleted' -Message "Plan execution finished (status: $runStatus)." -CorrelationId $corr -Actor $actor -Data @{
        Status    = $runStatus
        StepCount = @($Plan.Steps).Count
    }) -EventSink $EventSink -EventBuffer $events

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

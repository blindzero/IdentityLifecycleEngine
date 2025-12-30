function Invoke-IdleStepEmitEvent {
    <#
    .SYNOPSIS
    Emits a custom event (demo step).

    .DESCRIPTION
    This step does not change external state. It emits a custom event message.
    If the execution context provides an EventSink, the step will write to it.
    If no EventSink is available, the step will still succeed (no-op).

    This keeps the step host-agnostic and safe to use in demos/tests.

    .PARAMETER Context
    Execution context created by IdLE.Core.

    .PARAMETER Step
    The plan step object (Name, Type, With, When).

    .OUTPUTS
    PSCustomObject (PSTypeName: IdLE.StepResult)
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
        $with = @{}
    }

    $message = if ($with.ContainsKey('Message') -and -not [string]::IsNullOrWhiteSpace([string]$with.Message)) {
        [string]$with.Message
    }
    else {
        "Custom event emitted by step '$([string]$Step.Name)'."
    }

    # EventSink is optional. If it exists, it should accept an event object.
    # We deliberately do not assume a specific method name on the context itself.
    $sinkProp = $Context.PSObject.Properties['EventSink']
    if ($null -ne $sinkProp -and $null -ne $sinkProp.Value) {

        $eventObject = [pscustomobject]@{
            PSTypeName    = 'IdLE.Event'
            TimestampUtc  = [DateTime]::UtcNow
            Type          = 'Custom'
            StepName      = [string]$Step.Name
            Message       = $message
            Data          = @{
                StepType = [string]$Step.Type
            }
        }

        # Support common sink shapes:
        # - ScriptBlock: & $EventSink $event
        # - Object with method 'Add' or 'Write' or 'Emit'
        $sink = $sinkProp.Value

        if ($sink -is [scriptblock]) {
            & $sink $eventObject
        }
        elseif ($sink.PSObject.Methods.Name -contains 'Add') {
            $sink.Add($eventObject)
        }
        elseif ($sink.PSObject.Methods.Name -contains 'Write') {
            $sink.Write($eventObject)
        }
        elseif ($sink.PSObject.Methods.Name -contains 'Emit') {
            $sink.Emit($eventObject)
        }
        else {
            # Sink is present but has an unknown shape -> do not fail the step.
            # Host can decide how strictly it wants to enforce sink contract.
        }
    }

    return [pscustomobject]@{
        PSTypeName = 'IdLE.StepResult'
        Name       = [string]$Step.Name
        Type       = [string]$Step.Type
        Status     = 'Completed'
        Error      = $null
    }
}

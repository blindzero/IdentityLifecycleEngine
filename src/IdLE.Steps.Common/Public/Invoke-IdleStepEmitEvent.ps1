function Invoke-IdleStepEmitEvent {
    <#
    .SYNOPSIS
    Emits a workflow-defined event.

    .DESCRIPTION
    This step does not change external state. It writes one structured event to the
    EventSink on the execution context (buffered in the execution result and forwarded
    to the host event sink, if any).

    Inputs (all optional):
    - With.Message: event message. Defaults to "Event emitted by step '<Name>'.".
    - With.Type: event type, e.g. 'Contoso.Joiner.Notified'. Must not start with 'IdLE.'
      (reserved) and must not be 'Information', 'Warning', 'Error' or 'Custom'.
      Defaults to 'IdLE.Step.EmitEvent.Emitted'.
    - With.Level: 'Information' (default), 'Warning' or 'Error'.

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
        "Event emitted by step '$([string]$Step.Name)'."
    }

    $eventType = 'IdLE.Step.EmitEvent.Emitted'
    if ($with.ContainsKey('Type') -and -not [string]::IsNullOrWhiteSpace([string]$with.Type)) {
        $eventType = [string]$with.Type
        # 'IdLE.*' event types are reserved for events emitted by IdLE itself.
        if ($eventType.StartsWith('IdLE.', [System.StringComparison]::OrdinalIgnoreCase)) {
            throw [System.ArgumentException]::new(
                "ReservedNamespace: Event type '$eventType' uses the reserved prefix 'IdLE.'. Workflow-defined event types must not start with 'IdLE.'.",
                'With.Type'
            )
        }
    }

    $level = if ($with.ContainsKey('Level') -and -not [string]::IsNullOrWhiteSpace([string]$with.Level)) {
        [string]$with.Level
    }
    else {
        'Information'
    }

    # The engine provides an EventSink contract with a WriteEvent(...) method.
    # If the host is not interested in streaming events, the sink will still buffer events
    # for the execution result. This keeps the step deterministic and host-agnostic.
    if ($Context.PSObject.Properties.Name -contains 'EventSink' -and $null -ne $Context.EventSink) {
        if ($Context.EventSink.PSObject.Methods.Name -contains 'WriteEvent') {
            $Context.EventSink.WriteEvent($eventType, $message, [string]$Step.Name, @{ StepType = [string]$Step.Type }, $level)
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

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

    .PARAMETER With
    Validated With hashtable (Message, Type, Level).

    .PARAMETER Step
    Step metadata (Name, Type).

    .OUTPUTS
    None.
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
        [object] $Step
    )

    $message = if ($With.ContainsKey('Message')) { [string]$With.Message } else { "Event emitted by step '$([string]$Step.Name)'." }

    $eventType = 'IdLE.Step.EmitEvent.Emitted'
    if ($With.ContainsKey('Type')) {
        $eventType = [string]$With.Type
        # 'IdLE.*' event types are reserved for events emitted by IdLE itself.
        if ($eventType.StartsWith('IdLE.', [System.StringComparison]::OrdinalIgnoreCase)) {
            throw [System.ArgumentException]::new(
                "ReservedNamespace: Event type '$eventType' uses the reserved prefix 'IdLE.'. Workflow-defined event types must not start with 'IdLE.'.",
                'With.Type'
            )
        }
    }

    $Context.EventSink.WriteEvent($eventType, $message, [string]$Step.Name, @{ StepType = [string]$Step.Type }, [string]$With.Level)
}

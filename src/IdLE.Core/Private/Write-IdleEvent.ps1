function Write-IdleEvent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Event,

        [Parameter()]
        [AllowNull()]
        [object] $EventSink,

        [Parameter()]
        [AllowNull()]
        [System.Collections.Generic.List[object]] $EventBuffer
    )

    # If an event sink is provided, try to emit events immediately.
    # Supported shapes:
    # - ScriptBlock: invoked with the event as the only argument
    # - Object with method "WriteEvent": called as $EventSink.WriteEvent($Event)
    # - If nothing is provided: do nothing (events can still be buffered)
    if ($null -ne $EventSink) {
        if ($EventSink -is [scriptblock]) {
            & $EventSink $Event
        }
        elseif ($EventSink.PSObject.Methods.Name -contains 'WriteEvent') {
            $EventSink.WriteEvent($Event)
        }
    }

    # Buffer events for return value / tests if requested.
    if ($null -ne $EventBuffer) {
        [void]$EventBuffer.Add($Event)
    }
}

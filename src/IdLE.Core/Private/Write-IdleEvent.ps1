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

    # If an external event sink is provided, emit events immediately.
    # Security note: we do NOT support ScriptBlock sinks to avoid arbitrary code execution.
    # Supported shape:
    # - Object with method "WriteEvent": called as $EventSink.WriteEvent($Event)
    if ($null -ne $EventSink) {
        if ($EventSink -is [scriptblock]) {
            throw [System.ArgumentException]::new('EventSink must not be a ScriptBlock. Provide an object with a WriteEvent(event) method.', 'EventSink')
        }

        if (-not ($EventSink.PSObject.Methods.Name -contains 'WriteEvent')) {
            throw [System.ArgumentException]::new('EventSink must provide a WriteEvent(event) method.', 'EventSink')
        }

        $EventSink.WriteEvent($Event)
    }

    # Buffer events for return value / tests if requested.
    if ($null -ne $EventBuffer) {
        [void]$EventBuffer.Add($Event)
    }
}

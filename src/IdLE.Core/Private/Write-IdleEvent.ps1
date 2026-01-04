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

    # Redaction is an output-boundary concern:
    # - before sending to external sinks
    # - before buffering for later return values / tests
    #
    # We never mutate the original event object. We emit a redacted copy.
    $shouldEmitToSink = ($null -ne $EventSink)
    $shouldBuffer     = ($null -ne $EventBuffer)

    $eventToEmit = $Event
    if ($shouldEmitToSink -or $shouldBuffer) {
        # Copy-IdleRedactedObject lives in IdLE.Core/Private and is loaded into the module scope.
        # It performs deterministic, non-mutating redaction for known secret keys as well as
        # PSCredential/SecureString values.
        $eventToEmit = Copy-IdleRedactedObject -Value $Event
    }

    # Emit to external sink if provided.
    if ($shouldEmitToSink) {

        # We intentionally do not accept scriptblocks as sinks to avoid hidden execution.
        if ($EventSink -is [scriptblock]) {
            throw [System.ArgumentException]::new(
                'EventSink must not be a ScriptBlock. Provide an object with a WriteEvent(event) method.',
                'EventSink'
            )
        }

        # The sink contract is deliberately small:
        # an object exposing a WriteEvent(event) method.
        if (-not ($EventSink.PSObject.Methods.Name -contains 'WriteEvent')) {
            throw [System.ArgumentException]::new(
                'EventSink must provide a WriteEvent(event) method.',
                'EventSink'
            )
        }

        # Always emit the redacted copy (output boundary).
        $EventSink.WriteEvent($eventToEmit)
    }

    # Buffer events for return value / tests if requested.
    if ($shouldBuffer) {
        # Always buffer the redacted copy (output boundary).
        [void]$EventBuffer.Add($eventToEmit)
    }
}
function New-IdleEventSink {
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'EventBuffer', Justification = 'Passed to Write-IdleEvent via closure.')]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $CorrelationId,

        [Parameter()]
        [AllowNull()]
        [string] $Actor,

        [Parameter()]
        [AllowNull()]
        [object] $ExternalEventSink,

        [Parameter()]
        [AllowNull()]
        [System.Collections.Generic.List[object]] $EventBuffer
    )

    # External sinks are host-provided extension points.
    # We validate strictly to keep the engine deterministic and to avoid code execution.
    if ($null -ne $ExternalEventSink) {
        if ($ExternalEventSink -is [scriptblock]) {
            throw [System.ArgumentException]::new(
                'ExternalEventSink must not be a ScriptBlock. Provide an object with a WriteEvent(event) method.',
                'ExternalEventSink'
            )
        }

        if (-not ($ExternalEventSink.PSObject.Methods.Name -contains 'WriteEvent')) {
            throw [System.ArgumentException]::new(
                'ExternalEventSink must provide a WriteEvent(event) method.',
                'ExternalEventSink'
            )
        }
    }

    # Capture command references once to avoid scope/name resolution issues inside script methods.
    $newIdleEventCmd = Get-Command -Name 'New-IdleEvent'   -CommandType Function -ErrorAction Stop
    $writeIdleEventCmd = Get-Command -Name 'Write-IdleEvent' -CommandType Function -ErrorAction Stop

    $sink = [pscustomobject]@{
        PSTypeName    = 'IdLE.EventSink'
        CorrelationId = $CorrelationId
        Actor         = $Actor
    }

    # Provide a stable, object-based contract to steps.
    # Steps call: $Context.EventSink.WriteEvent(Type, Message, StepName, Data)
    # The engine stays in control of event shape and buffering.
    $writeMethod = {
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $Type,

            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $Message,

            [Parameter()]
            [AllowNull()]
            [string] $StepName,

            [Parameter()]
            [AllowNull()]
            [hashtable] $Data
        )

        $evt = & $newIdleEventCmd -Type $Type -Message $Message -CorrelationId $CorrelationId -Actor $Actor -StepName $StepName -Data $Data
        & $writeIdleEventCmd -Event $evt -EventSink $ExternalEventSink -EventBuffer $EventBuffer
    }.GetNewClosure()

    $null = Add-Member -InputObject $sink -MemberType ScriptMethod -Name 'WriteEvent' -Value $writeMethod -Force

    return $sink
}

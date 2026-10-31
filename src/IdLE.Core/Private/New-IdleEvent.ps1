function New-IdleEvent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Type,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Message,

        [Parameter()]
        [AllowNull()]
        [string] $CorrelationId,

        [Parameter()]
        [AllowNull()]
        [string] $Actor,

        [Parameter()]
        [AllowNull()]
        [string] $StepName,

        [Parameter()]
        [AllowNull()]
        [hashtable] $Data,

        [Parameter()]
        [ValidateSet('Information', 'Warning', 'Error')]
        [string] $Level = 'Information'
    )

    # Severity belongs in Level, not in Type. These former catch-all types carry no meaning for sinks
    # that filter by type, so they are rejected (see docs/extend/events.md).
    if ((Get-IdleReservedNamespaces).EventType.Disallowed -contains $Type) {
        throw [System.ArgumentException]::new(
            "Event type '$Type' is not allowed. Use a descriptive type such as 'IdLE.<Area>.<Event>' or '<Owner>.IdLE.<Area>.<Event>' and pass the severity as Level.",
            'Type'
        )
    }

    # Create a structured event object that can be streamed to an audit sink later.
    return [pscustomobject]@{
        PSTypeName    = 'IdLE.Event'
        TimestampUtc  = [DateTime]::UtcNow
        Type          = $Type
        Level         = $Level
        Message       = $Message
        CorrelationId = $CorrelationId
        Actor         = $Actor
        StepName      = $StepName
        Data          = $Data
    }
}

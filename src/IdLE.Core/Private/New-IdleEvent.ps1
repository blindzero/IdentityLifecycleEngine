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
        [hashtable] $Data
    )

    # Create a structured event object that can be streamed to an audit sink later.
    return [pscustomobject]@{
        PSTypeName    = 'IdLE.Event'
        TimestampUtc  = [DateTime]::UtcNow
        Type          = $Type
        Message       = $Message
        CorrelationId = $CorrelationId
        Actor         = $Actor
        StepName      = $StepName
        Data          = $Data
    }
}

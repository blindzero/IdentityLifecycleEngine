function Invoke-IdleStepEmitEvent {
    <#
    .SYNOPSIS
    Emits a custom event (demo step).

    .DESCRIPTION
    This step does not change any external state. It simply emits a custom event message.
    It is used as a reference implementation for the step plugin contract.

    .PARAMETER Context
    Execution context (Request, Plan, Providers, EventSink, CorrelationId, Actor).

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

    $message = $null
    if ($Step.PSObject.Properties.Name -contains 'With' -and $null -ne $Step.With) {
        if ($Step.With -is [hashtable] -and $Step.With.ContainsKey('Message')) {
            $message = [string]$Step.With.Message
        }
    }

    if ([string]::IsNullOrWhiteSpace($message)) {
        $message = "EmitEvent step executed."
    }

    # Emit a custom event through the engine event sink.
    if ($Context.PSObject.Properties.Name -contains 'WriteEvent') {
        $Context.WriteEvent('Custom', $message, $Step.Name, @{ StepType = $Step.Type })
    }

    return [pscustomobject]@{
        PSTypeName = 'IdLE.StepResult'
        Name       = [string]$Step.Name
        Type       = [string]$Step.Type
        Status     = 'Completed'
        Error      = $null
    }
}

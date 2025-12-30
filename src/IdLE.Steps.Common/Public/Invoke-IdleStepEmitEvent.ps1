function Invoke-IdleStepEmitEvent {
    <#
    .SYNOPSIS
    Emits a custom event (demo step).

    .DESCRIPTION
    This step does not change external state. It emits a custom event message.
    The engine provides an EventSink on the execution context that the step can use
    to write structured events.

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

    # The engine provides an EventSink contract with a WriteEvent(...) method.
    # If the host is not interested in streaming events, the sink will still buffer events
    # for the execution result. This keeps the step deterministic and host-agnostic.
    if ($Context.PSObject.Properties.Name -contains 'EventSink' -and $null -ne $Context.EventSink) {
        if ($Context.EventSink.PSObject.Methods.Name -contains 'WriteEvent') {
            $Context.EventSink.WriteEvent('Custom', $message, [string]$Step.Name, @{ StepType = [string]$Step.Type })
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

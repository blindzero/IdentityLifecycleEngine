function ConvertTo-IdleStepResult {
    <#
    .SYNOPSIS
    Builds an IdLE.StepResult from a step handler's output.

    .DESCRIPTION
    Handlers return $null or a hashtable with the optional keys Changed (Bool), Data (Hashtable) and
    State (Hashtable). Failures are reported by throwing, never by the return value.
    Any other output fails with InvalidStepHandlerResult.

    .PARAMETER Output
    Handler output (as captured from the pipeline).

    .PARAMETER StepName
    Step name.

    .PARAMETER StepType
    Step type.

    .PARAMETER Attempts
    Number of attempts (retries included).

    .PARAMETER Source
    Handler provenance (ConvertTo-IdleSourceInfo).

    .OUTPUTS
    PSCustomObject (PSTypeName: IdLE.StepResult)
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object] $Output,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $StepName,

        [Parameter(Mandatory)]
        [string] $StepType,

        [Parameter(Mandatory)]
        [int] $Attempts,

        [Parameter()]
        [AllowNull()]
        [object] $Source
    )

    $prefix = "InvalidStepHandlerResult: Step '$StepName' (type '$StepType')"

    # A handler that leaks pipeline output (e.g. an unassigned method call) returns several objects.
    if ($Output -is [array]) {
        throw [System.InvalidOperationException]::new(
            "$prefix wrote $($Output.Count) objects to the output stream. Return a single hashtable (@{ Changed; Data; State }) or nothing; assign or discard other output with `$null = ..."
        )
    }

    $changed = $false
    $data = $null
    $state = $null

    if ($null -ne $Output) {
        if ($Output -isnot [System.Collections.IDictionary]) {
            throw [System.InvalidOperationException]::new(
                "$prefix returned a [$($Output.GetType().Name)]. Return a hashtable (@{ Changed; Data; State }) or nothing; report failures by throwing."
            )
        }

        foreach ($key in $Output.PSBase.Keys) {
            if (@('Changed', 'Data', 'State') -notcontains [string]$key) {
                throw [System.InvalidOperationException]::new("$prefix returned unknown key '$key'. Supported keys: Changed, Data, State.")
            }
        }

        if ($Output.Contains('Changed') -and $null -ne $Output['Changed']) {
            if ($Output['Changed'] -isnot [bool]) {
                throw [System.InvalidOperationException]::new("$prefix returned Changed of type [$($Output['Changed'].GetType().Name)]; expected a Bool.")
            }
            $changed = $Output['Changed']
        }

        foreach ($key in @('Data', 'State')) {
            if ($Output.Contains($key) -and $null -ne $Output[$key] -and $Output[$key] -isnot [System.Collections.IDictionary]) {
                throw [System.InvalidOperationException]::new("$prefix returned $key of type [$($Output[$key].GetType().Name)]; expected a Hashtable.")
            }
        }

        if ($Output.Contains('Data')) { $data = $Output['Data'] }
        if ($Output.Contains('State')) { $state = $Output['State'] }
    }

    return [pscustomobject]@{
        PSTypeName = 'IdLE.StepResult'
        Name       = $StepName
        Type       = $StepType
        Status     = 'Completed'
        Changed    = $changed
        Data       = $data
        State      = $state
        Error      = $null
        Attempts   = $Attempts
        Source     = $Source
    }
}

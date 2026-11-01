function Resolve-IdleDeferredStepWith {
    <#
    .SYNOPSIS
    Resolves a plan step's deferred With templates (State placeholders) right before the step runs.

    .DESCRIPTION
    Planning keeps With strings that contain State placeholders unresolved and records them in
    IdLE.PlanStep.DeferredWith (Path, Segments, Schema). This function resolves each recorded string
    against Request and State in one pass, validates the result against the recorded key schema and
    returns a copy of the step with the effective With. The plan step itself is not modified.

    Only recorded strings are resolved: values that were resolved at planning time (e.g. request data)
    are never scanned for templates again.

    Errors start with StateReferenceUnresolved (missing or $null State value) or the With schema codes.

    .PARAMETER Step
    Plan step.

    .PARAMETER Request
    Request snapshot of the plan.

    .PARAMETER State
    State published by earlier steps (step name -> State hashtable).

    .OUTPUTS
    The plan step, or a copy of it with the resolved With.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Step,

        [Parameter()]
        [AllowNull()]
        [object] $Request,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [System.Collections.IDictionary] $State
    )

    $deferredWith = @(Get-IdlePropertyValue -Object $Step -Name 'DeferredWith' | Where-Object { $null -ne $_ })
    if ($deferredWith.Count -eq 0) {
        return $Step
    }

    $stepName = [string](Get-IdlePropertyValue -Object $Step -Name 'Name')
    $stepType = [string](Get-IdlePropertyValue -Object $Step -Name 'Type')
    $effectiveRequest = if ($null -ne $Request) { $Request } else { [pscustomobject]@{} }

    function Get-IdleChildValue {
        param([object] $Parent, [object] $Segment)
        if ($Parent -is [System.Collections.IDictionary]) { return $Parent[$Segment] }
        if ($Parent -is [array]) { return $Parent[[int]$Segment] }
        return $Parent.PSObject.Properties[[string]$Segment].Value
    }

    function Set-IdleChildValue {
        param([object] $Parent, [object] $Segment, [object] $Value)
        if ($Parent -is [System.Collections.IDictionary]) { $Parent[$Segment] = $Value; return }
        if ($Parent -is [array]) { $Parent[[int]$Segment] = $Value; return }
        $Parent.PSObject.Properties[[string]$Segment].Value = $Value
    }

    $with = Copy-IdleDataObject -Value (Get-IdlePropertyValue -Object $Step -Name 'With')

    foreach ($entry in $deferredWith) {
        $segments = @(Get-IdlePropertyValue -Object $entry -Name 'Segments')
        $path = [string](Get-IdlePropertyValue -Object $entry -Name 'Path')
        $schema = Get-IdlePropertyValue -Object $entry -Name 'Schema'

        $parent = $with
        for ($i = 0; $i -lt $segments.Count - 1; $i++) {
            $parent = Get-IdleChildValue -Parent $parent -Segment $segments[$i]
        }
        $lastSegment = $segments[$segments.Count - 1]

        $value = Resolve-IdleTemplateString -Value (Get-IdleChildValue -Parent $parent -Segment $lastSegment) -Request $effectiveRequest -StepName $stepName -State $State
        if ($schema -is [System.Collections.IDictionary]) {
            $value = ConvertTo-IdleSchemaValue -Schema ([hashtable]$schema) -Value $value -Path $path -ErrorPrefix ("Step '{0}' (type '{1}'):" -f $stepName, $stepType)
        }

        Set-IdleChildValue -Parent $parent -Segment $lastSegment -Value $value
    }

    $effectiveStep = $Step.PSObject.Copy()
    $effectiveStep.With = $with
    return $effectiveStep
}

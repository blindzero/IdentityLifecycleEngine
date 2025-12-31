<#
.SYNOPSIS
Maps an internal LifecyclePlan object to the canonical Plan Export contract DTO.

.DESCRIPTION
This is the single source of truth for the Plan Export JSON contract mapping.
It produces a pure data object (ordered hashtables) that can be serialized to JSON
deterministically.

Notes:
- Engine version is intentionally omitted to avoid noise on module version bumps.
- Plan timestamps are intentionally omitted to keep Golden/Snapshot tests stable.
  Contract versioning is done via schemaVersion.

The mapping is defensive and accepts multiple internal property names to reduce coupling
to internal refactors.
#>
function ConvertTo-IdlePlanExportObject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Plan
    )

    function Get-FirstPropertyValue {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [object] $Object,

            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string[]] $Names
        )

        foreach ($name in $Names) {
            $prop = $Object.PSObject.Properties[$name]
            if ($null -ne $prop) {
                return $prop.Value
            }
        }

        return $null
    }

    function New-OrderedMap {
        [CmdletBinding()]
        param()

        return [ordered] @{}
    }

    # ---- Engine block --------------------------------------------------------
    # Export engine name only. Contract versioning is done via schemaVersion.
    $engineMap = New-OrderedMap
    $engineMap.name = 'IdLE'

    # ---- Request block -------------------------------------------------------
    # Prefer an explicit request object if present. Otherwise, fall back to plan fields.
    $request = Get-FirstPropertyValue -Object $Plan -Names @('Request', 'LifecycleRequest', 'InputRequest')

    $requestType = $null
    $correlationId = $null
    $actor = $null
    $requestInput = $null

    if ($null -ne $request) {
        $requestType   = Get-FirstPropertyValue -Object $request -Names @('Type', 'RequestType', 'LifecycleType', 'Kind', 'LifecycleEvent')
        $correlationId = Get-FirstPropertyValue -Object $request -Names @('CorrelationId', 'CorrelationID', 'Correlation', 'Id')
        $actor         = Get-FirstPropertyValue -Object $request -Names @('Actor', 'RequestedBy', 'Source', 'Origin')

        # Keep input opaque. We do not transform or validate here.
        $requestInput  = Get-FirstPropertyValue -Object $request -Names @('Input', 'Data', 'Payload', 'Attributes')
    }
    else {
        # Plan-shaped fallback (current IdLE plan object shape).
        $requestType   = Get-FirstPropertyValue -Object $Plan -Names @('LifecycleEvent', 'Type', 'RequestType')
        $correlationId = Get-FirstPropertyValue -Object $Plan -Names @('CorrelationId', 'CorrelationID', 'Id', 'PlanId', 'PlanID')
        $actor         = Get-FirstPropertyValue -Object $Plan -Names @('Actor', 'RequestedBy')
        $requestInput  = $null
    }

    $requestMap = New-OrderedMap
    $requestMap.type          = $requestType
    $requestMap.correlationId = $correlationId
    $requestMap.actor         = $actor
    $requestMap.input         = $requestInput

    # ---- Plan block ----------------------------------------------------------
    # Keep plan id stable and aligned with the internal plan identity.
    $planId = Get-FirstPropertyValue -Object $Plan -Names @('Id', 'PlanId', 'PlanID', 'CorrelationId', 'CorrelationID')
    $mode   = Get-FirstPropertyValue -Object $Plan -Names @('Mode', 'State', 'Status')

    # Plan timestamps are intentionally omitted for contract stability (Golden tests).
    $steps = Get-FirstPropertyValue -Object $Plan -Names @('Steps', 'Items', 'PlanSteps', 'Entries')
    if ($null -eq $steps) {
        $steps = @()
    }

    $stepList = @()
    $index = 0

    foreach ($step in $steps) {
        $index++

        if ($null -eq $step) {
            continue
        }

        $stepId = Get-FirstPropertyValue -Object $step -Names @('Id', 'StepId', 'StepID')
        if ([string]::IsNullOrWhiteSpace([string] $stepId)) {
            # Deterministic fallback id when none exists.
            $stepId = ('step-{0:00}' -f $index)
        }

        $stepName = Get-FirstPropertyValue -Object $step -Names @('Name', 'DisplayName', 'Title')
        $stepType = Get-FirstPropertyValue -Object $step -Names @('StepType', 'Type', 'Kind')
        $provider = Get-FirstPropertyValue -Object $step -Names @('Provider', 'ProviderName', 'Adapter', 'Target')

        # Conditions: export declaratively, without evaluation.
        # Current plan object shows Condition = $null, so we default to "always".
        $condition = Get-FirstPropertyValue -Object $step -Names @('Condition', 'When', 'Applicability', 'Guard')

        $conditionMap = $null
        if ($null -ne $condition) {
            $conditionType = Get-FirstPropertyValue -Object $condition -Names @('Type', 'Kind')
            $expression    = Get-FirstPropertyValue -Object $condition -Names @('Expression', 'Expr', 'Query')

            $conditionMap = New-OrderedMap
            $conditionMap.type = $conditionType
            $conditionMap.expression = $expression
        }
        else {
            $conditionMap = New-OrderedMap
            $conditionMap.type = 'always'
            $conditionMap.expression = $null
        }

        # Inputs and expected state are treated as opaque, pure data.
        # Current plan uses 'With' for inputs.
        $inputs = Get-FirstPropertyValue -Object $step -Names @('Inputs', 'Input', 'Parameters', 'Arguments', 'With')
        $expectedState = Get-FirstPropertyValue -Object $step -Names @('ExpectedState', 'DesiredState', 'TargetState', 'State')

        $stepMap = New-OrderedMap
        $stepMap.id = $stepId
        $stepMap.name = $stepName
        $stepMap.stepType = $stepType
        $stepMap.provider = $provider
        $stepMap.condition = $conditionMap
        $stepMap.inputs = $inputs
        $stepMap.expectedState = $expectedState

        $stepList += $stepMap
    }

    $planMap = New-OrderedMap
    $planMap.id = $planId
    $planMap.mode = $mode
    $planMap.steps = $stepList

    # ---- Metadata block ------------------------------------------------------
    $metadataMap = New-OrderedMap
    $metadataMap.generatedBy = 'Export-IdlePlanObject'
    $metadataMap.environment = $null
    $metadataMap.labels = @()

    # ---- Root ---------------------------------------------------------------
    $root = New-OrderedMap
    $root.schemaVersion = '1.0'
    $root.engine = $engineMap
    $root.request = $requestMap
    $root.plan = $planMap
    $root.metadata = $metadataMap

    return $root
}

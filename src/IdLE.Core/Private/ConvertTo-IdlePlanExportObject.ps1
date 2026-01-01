<#
.SYNOPSIS
Maps an internal LifecyclePlan object to the canonical Plan Export contract DTO.

.DESCRIPTION
This function is the single source of truth for the Plan Export JSON contract mapping.
It produces a pure data object (ordered hashtables) that can be serialized to JSON
deterministically.

Contract stability decisions:
- engine.version is intentionally omitted (avoid noise on module version bumps)
- plan.createdAt is intentionally omitted (avoid non-deterministic timestamps in exports)
- empty strings are normalized to $null for identifier-like fields (e.g., actor)

The mapping is defensive and supports multiple internal property names to reduce coupling
to internal refactors.
#>
function ConvertTo-IdlePlanExportObject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Plan
    )

    function New-OrderedMap {
        [CmdletBinding()]
        param()
        return [ordered] @{}
    }

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

    function ConvertTo-NullIfEmptyString {
        [CmdletBinding()]
        param(
            [Parameter()]
            [object] $Value
        )

        if ($null -eq $Value) {
            return $null
        }

        if ($Value -is [string] -and [string]::IsNullOrWhiteSpace($Value)) {
            return $null
        }

        return $Value
    }

    # ---- Engine block --------------------------------------------------------
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
        $requestType = ConvertTo-NullIfEmptyString -Value (
            Get-FirstPropertyValue -Object $request -Names @('Type', 'RequestType', 'LifecycleType', 'Kind', 'LifecycleEvent')
        )

        $correlationId = ConvertTo-NullIfEmptyString -Value (
            Get-FirstPropertyValue -Object $request -Names @('CorrelationId', 'CorrelationID', 'Correlation', 'Id')
        )

        $actor = ConvertTo-NullIfEmptyString -Value (
            Get-FirstPropertyValue -Object $request -Names @('Actor', 'RequestedBy', 'Source', 'Origin')
        )

        # Keep input opaque. We do not transform or validate here.
        $requestInput = Get-FirstPropertyValue -Object $request -Names @('Input', 'Data', 'Payload', 'Attributes')

        if ($null -eq $requestInput) {
            # IdLE lifecycle requests store business intent as IdentityKeys/DesiredState/Changes.
            # When present, export these as the canonical request.input payload.
            $identityKeys = Get-FirstPropertyValue -Object $request -Names @('IdentityKeys', 'IdentityKey', 'Keys')
            $desiredState = Get-FirstPropertyValue -Object $request -Names @('DesiredState', 'TargetState')
            $changes      = Get-FirstPropertyValue -Object $request -Names @('Changes', 'Delta')

            if ($null -ne $identityKeys -or $null -ne $desiredState -or $null -ne $changes) {
                $requestInput = New-OrderedMap
                $requestInput.identityKeys = $identityKeys
                $requestInput.desiredState = $desiredState
                $requestInput.changes      = $changes
            }
        }
    }
    else {
        # Plan-shaped fallback (current IdLE plan object shape).
        $requestType = ConvertTo-NullIfEmptyString -Value (
            Get-FirstPropertyValue -Object $Plan -Names @('LifecycleEvent', 'Type', 'RequestType')
        )

        $correlationId = ConvertTo-NullIfEmptyString -Value (
            Get-FirstPropertyValue -Object $Plan -Names @('CorrelationId', 'CorrelationID', 'Id', 'PlanId', 'PlanID')
        )

        $actor = ConvertTo-NullIfEmptyString -Value (
            Get-FirstPropertyValue -Object $Plan -Names @('Actor', 'RequestedBy')
        )

        $requestInput = $null
    }

    $requestMap = New-OrderedMap
    $requestMap.type          = $requestType
    $requestMap.correlationId = $correlationId
    $requestMap.actor         = $actor
    $requestMap.input         = $requestInput

    # ---- Plan block ----------------------------------------------------------
    $planId = ConvertTo-NullIfEmptyString -Value (
        Get-FirstPropertyValue -Object $Plan -Names @('Id', 'PlanId', 'PlanID', 'CorrelationId', 'CorrelationID')
    )

    $mode = ConvertTo-NullIfEmptyString -Value (
        Get-FirstPropertyValue -Object $Plan -Names @('Mode', 'State', 'Status')
    )

    # plan.createdAt is intentionally omitted (non-deterministic in current implementation)

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

        $stepId = ConvertTo-NullIfEmptyString -Value (
            Get-FirstPropertyValue -Object $step -Names @('Id', 'StepId', 'StepID')
        )

        if ([string]::IsNullOrWhiteSpace([string] $stepId)) {
            # Deterministic fallback id when none exists.
            $stepId = ('step-{0:00}' -f $index)
        }

        $stepName = ConvertTo-NullIfEmptyString -Value (
            Get-FirstPropertyValue -Object $step -Names @('Name', 'DisplayName', 'Title')
        )

        $stepType = ConvertTo-NullIfEmptyString -Value (
            Get-FirstPropertyValue -Object $step -Names @('StepType', 'Type', 'Kind')
        )

        $provider = ConvertTo-NullIfEmptyString -Value (
            Get-FirstPropertyValue -Object $step -Names @('Provider', 'ProviderName', 'Adapter', 'Target')
        )

        # Conditions are exported declaratively without evaluation.
        $condition = Get-FirstPropertyValue -Object $step -Names @('Condition', 'When', 'Applicability', 'Guard')

        if ($null -ne $condition) {
            $conditionType = ConvertTo-NullIfEmptyString -Value (
                Get-FirstPropertyValue -Object $condition -Names @('Type', 'Kind')
            )

            $expression = ConvertTo-NullIfEmptyString -Value (
                Get-FirstPropertyValue -Object $condition -Names @('Expression', 'Expr', 'Query')
            )

            $conditionMap = New-OrderedMap
            $conditionMap.type = $conditionType
            $conditionMap.expression = $expression
        }
        else {
            $conditionMap = New-OrderedMap
            $conditionMap.type = 'always'
            $conditionMap.expression = $null
        }

        # Inputs and expectedState are treated as opaque, pure data.
        # Current IdLE plan object shape uses 'With' for inputs.
        $inputs = Get-FirstPropertyValue -Object $step -Names @('Inputs', 'Input', 'Parameters', 'Arguments', 'With')
        $expectedState = Get-FirstPropertyValue -Object $step -Names @('ExpectedState', 'DesiredState', 'TargetState')

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

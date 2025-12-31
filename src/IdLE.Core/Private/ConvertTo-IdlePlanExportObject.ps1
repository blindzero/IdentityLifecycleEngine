<#
.SYNOPSIS
Maps an internal LifecyclePlan object to the canonical Plan Export contract DTO.

.DESCRIPTION
This is the single source of truth for the Plan Export JSON contract mapping.
It produces a pure data object (ordered hashtables / PSCustomObject compatible) that can be
serialized to JSON deterministically.

The mapping is intentionally defensive:
- It supports multiple plausible internal property names (to reduce coupling to internal refactors).
- It does not depend on host/runtime-specific objects.
- It never emits executable PowerShell objects (script blocks, delegates, etc.).

The JSON serializer (ConvertTo-Json) is called by the public cmdlet.
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

    function ConvertTo-Iso8601UtcString {
        [CmdletBinding()]
        param(
            [Parameter()]
            [object] $Value
        )

        if ($null -eq $Value) {
            return $null
        }

        # Accept DateTime / DateTimeOffset; otherwise keep as-is (string) to avoid lossy coercion.
        if ($Value -is [datetime]) {
            return ([datetime]::SpecifyKind($Value, [DateTimeKind]::Utc)).ToString("o")
        }

        if ($Value -is [DateTimeOffset]) {
            return $Value.ToUniversalTime().ToString("o")
        }

        return [string] $Value
    }

    # ---- Engine block --------------------------------------------------------
    # We expose engine name/version for informational purposes only.
    $engineName = 'IdLE'
    $engineVersion = $null

    # Prefer module version if available; otherwise leave null (the contract version is schemaVersion).
    $moduleVersion = $MyInvocation.MyCommand.Module.Version
    if ($null -ne $moduleVersion) {
        $engineVersion = [string] $moduleVersion
    }

    # ---- Request block -------------------------------------------------------
    $request = Get-FirstPropertyValue -Object $Plan -Names @('Request', 'LifecycleRequest', 'InputRequest')

    $requestType = $null
    $correlationId = $null
    $actor = $null
    $requestInput = $null

    if ($null -ne $request) {
        $requestType   = Get-FirstPropertyValue -Object $request -Names @('Type', 'RequestType', 'LifecycleType', 'Kind')
        $correlationId = Get-FirstPropertyValue -Object $request -Names @('CorrelationId', 'CorrelationID', 'Correlation', 'Id')
        $actor         = Get-FirstPropertyValue -Object $request -Names @('Actor', 'RequestedBy', 'Source', 'Origin')

        # Keep input opaque. We do not transform or validate here.
        $requestInput  = Get-FirstPropertyValue -Object $request -Names @('Input', 'Data', 'Payload', 'Attributes')
    }

    $requestMap = New-OrderedMap
    $requestMap.type          = $requestType
    $requestMap.correlationId = $correlationId
    $requestMap.actor         = $actor
    $requestMap.input         = $requestInput

    # ---- Plan block ----------------------------------------------------------
    $planId = Get-FirstPropertyValue -Object $Plan -Names @('Id', 'PlanId', 'PlanID', 'CorrelationId')
    $createdAt = Get-FirstPropertyValue -Object $Plan -Names @('CreatedAt', 'CreatedOn', 'Timestamp', 'PlannedAt')
    $mode = Get-FirstPropertyValue -Object $Plan -Names @('Mode', 'State', 'Status')

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
            # Use a deterministic fallback id when none exists.
            $stepId = ('step-{0:00}' -f $index)
        }

        $stepName = Get-FirstPropertyValue -Object $step -Names @('Name', 'DisplayName', 'Title')
        $stepType = Get-FirstPropertyValue -Object $step -Names @('StepType', 'Type', 'Kind')
        $provider = Get-FirstPropertyValue -Object $step -Names @('Provider', 'ProviderName', 'Adapter', 'Target')

        # Conditions: export as declarative object, without evaluation.
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
            # If no condition exists, represent unconditional applicability explicitly.
            $conditionMap = New-OrderedMap
            $conditionMap.type = 'always'
            $conditionMap.expression = $null
        }

        # Inputs and expected state are treated as opaque, pure data.
        $inputs = Get-FirstPropertyValue -Object $step -Names @('Inputs', 'Input', 'Parameters', 'Arguments')
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
    $planMap.createdAt = ConvertTo-Iso8601UtcString -Value $createdAt
    $planMap.mode = $mode
    $planMap.steps = $stepList

    # ---- Metadata block ------------------------------------------------------
    # Metadata is optional and must not carry engine semantics.
    $metadata = New-OrderedMap
    $metadata.generatedBy = 'Export-IdlePlanObject'
    $metadata.environment = $null
    $metadata.labels = @()

    # ---- Root ---------------------------------------------------------------
    $engineMap = New-OrderedMap
    $engineMap.name = $engineName
    $engineMap.version = $engineVersion

    $root = New-OrderedMap
    $root.schemaVersion = '1.0'
    $root.engine = $engineMap
    $root.request = $requestMap
    $root.plan = $planMap
    $root.metadata = $metadata

    return $root
}

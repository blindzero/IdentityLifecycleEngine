function New-IdlePlanObject {
    <#
    .SYNOPSIS
    Builds a deterministic plan from a request and a workflow definition.

    .DESCRIPTION
    Loads and validates the workflow definition (PSD1) and creates a normalized plan object.
    This is a planning-only artifact. Execution is handled by Invoke-IdlePlan later.

    .PARAMETER WorkflowPath
    Path to the workflow definition (PSD1).

    .PARAMETER Request
    Lifecycle request object (must contain LifecycleEvent and CorrelationId).

    .PARAMETER Providers
    Provider map passed through to the plan for later execution.

    .OUTPUTS
    PSCustomObject (PSTypeName: IdLE.Plan)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $WorkflowPath,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Request,

        [Parameter()]
        [AllowNull()]
        [object] $Providers
    )

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

    function Copy-IdleDataObject {
        [CmdletBinding()]
        param(
            [Parameter()]
            [object] $Value
        )

        if ($null -eq $Value) {
            return $null
        }

        # Primitive / immutable-ish types can be returned as-is.
        if ($Value -is [string] -or
            $Value -is [int] -or
            $Value -is [long] -or
            $Value -is [double] -or
            $Value -is [decimal] -or
            $Value -is [bool] -or
            $Value -is [datetime] -or
            $Value -is [guid]) {
            return $Value
        }

        # Hashtable / IDictionary -> clone recursively.
        if ($Value -is [System.Collections.IDictionary]) {
            $copy = @{}
            foreach ($k in $Value.Keys) {
                $copy[$k] = Copy-IdleDataObject -Value $Value[$k]
            }
            return $copy
        }

        # Arrays / enumerables -> clone recursively.
        if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
            $items = @()
            foreach ($item in $Value) {
                $items += Copy-IdleDataObject -Value $item
            }
            return $items
        }

        # PSCustomObject and other objects -> shallow map of public properties (data-only).
        $props = $Value.PSObject.Properties | Where-Object { $_.MemberType -eq 'NoteProperty' -or $_.MemberType -eq 'Property' }
        if ($null -ne $props -and @($props).Count -gt 0) {
            $copy = @{}
            foreach ($p in $props) {
                $copy[$p.Name] = Copy-IdleDataObject -Value $p.Value
            }
            return [pscustomobject] $copy
        }

        # Fallback: return string representation (keeps export stable without leaking runtime handles).
        return [string] $Value
    }

    # Ensure required request properties exist without hard-typing the request class.
    $reqProps = $Request.PSObject.Properties.Name
    if ($reqProps -notcontains 'LifecycleEvent') {
        throw [System.ArgumentException]::new("Request object must contain property 'LifecycleEvent'.", 'Request')
    }
    if ($reqProps -notcontains 'CorrelationId') {
        throw [System.ArgumentException]::new("Request object must contain property 'CorrelationId'.", 'Request')
    }

    # Create a data-only snapshot of the incoming request.
    # This is required for auditing/approvals and for deterministic plan export artifacts.
    # We intentionally store a snapshot (not a reference) to avoid accidental mutations later.
    $requestSnapshot = [pscustomobject]@{
        PSTypeName     = 'IdLE.LifecycleRequestSnapshot'
        LifecycleEvent = ConvertTo-NullIfEmptyString -Value ([string] $Request.LifecycleEvent)
        CorrelationId  = ConvertTo-NullIfEmptyString -Value ([string] $Request.CorrelationId)
        Actor          = if ($reqProps -contains 'Actor') { ConvertTo-NullIfEmptyString -Value ([string] $Request.Actor) } else { $null }
        IdentityKeys   = if ($reqProps -contains 'IdentityKeys') { Copy-IdleDataObject -Value $Request.IdentityKeys } else { $null }
        DesiredState   = if ($reqProps -contains 'DesiredState') { Copy-IdleDataObject -Value $Request.DesiredState } else { $null }
        Changes        = if ($reqProps -contains 'Changes') { Copy-IdleDataObject -Value $Request.Changes } else { $null }
    }

    # Validate workflow and ensure it matches the request's LifecycleEvent.
    $workflow = Test-IdleWorkflowDefinitionObject -WorkflowPath $WorkflowPath -Request $Request

    # Create the plan object (planning artifact).
    # Steps will be populated after we have a stable plan context for condition evaluation.
    $plan = [pscustomobject]@{
        PSTypeName     = 'IdLE.Plan'
        WorkflowName   = [string]$workflow.Name
        LifecycleEvent = [string]$workflow.LifecycleEvent
        CorrelationId  = [string]$requestSnapshot.CorrelationId
        Request        = $requestSnapshot
        Actor          = $requestSnapshot.Actor
        CreatedUtc     = [DateTime]::UtcNow
        Steps          = @()
        Actions        = @()
        Warnings       = @()
        Providers      = $Providers
    }

    # Build a planning context for condition evaluation.
    # This allows conditions to reference "Plan.*" paths (e.g. Plan.LifecycleEvent).
    $planningContext = [pscustomobject]@{
        Plan     = $plan
        Request  = $Request
        Workflow = $workflow
    }

    # Normalize steps into a stable internal representation.
    # We deliberately keep step entries as PSCustomObject to avoid cross-module class loading issues.
    # Step conditions are evaluated during planning and may mark steps as NotApplicable.
    $normalizedSteps = @()
    foreach ($s in @($workflow.Steps)) {
        if (-not $s.ContainsKey('Name') -or [string]::IsNullOrWhiteSpace([string]$s.Name)) {
            throw [System.ArgumentException]::new('Workflow step is missing required key "Name".', 'Workflow')
        }
        if (-not $s.ContainsKey('Type') -or [string]::IsNullOrWhiteSpace([string]$s.Type)) {
            throw [System.ArgumentException]::new(("Workflow step '{0}' is missing required key 'Type'." -f [string]$s.Name), 'Workflow')
        }
        if ($s.ContainsKey('When')) {
            throw [System.ArgumentException]::new(
                "Workflow step '$($s.Name)' uses key 'When'. 'When' has been renamed to 'Condition'. Please update the workflow definition.",
                'Workflow'
            )
        }

        $condition = if ($s.ContainsKey('Condition')) { $s.Condition } else { $null }

        $status = 'Planned'
        if ($null -ne $condition) {
            $schemaErrors = Test-IdleConditionSchema -Condition $condition -StepName ([string]$s.Name)
            if (@($schemaErrors).Count -gt 0) {
                throw [System.ArgumentException]::new(
                    ("Invalid Condition on step '{0}': {1}" -f [string]$s.Name, ([string]::Join(' ', @($schemaErrors)))),
                    'Workflow'
                )
            }

            $isApplicable = Test-IdleCondition -Condition $condition -Context $planningContext
            if (-not $isApplicable) {
                $status = 'NotApplicable'
            }
        }

        $normalizedSteps += [pscustomobject]@{
            PSTypeName   = 'IdLE.PlanStep'
            Name         = [string]$s.Name
            Type         = [string]$s.Type
            Description  = if ($s.ContainsKey('Description')) { [string]$s.Description } else { '' }
            Condition    = $condition
            With         = if ($s.ContainsKey('With')) { $s.With } else { @{} }
            Status       = $status
        }
    }

    # Attach steps to the plan after normalization.
    $plan.Steps = $normalizedSteps

    return $plan
}

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

    function Normalize-IdleRequiredCapabilities {
        <#
        .SYNOPSIS
        Normalizes the optional RequiresCapabilities key from a workflow step.

        .DESCRIPTION
        A workflow step may declare required capabilities via RequiresCapabilities.
        Supported shapes:
        - missing / $null -> empty list
        - string -> single capability
        - array/enumerable of strings -> list of capabilities

        The output is a stable, sorted, unique string array.
        #>
        [CmdletBinding()]
        param(
            [Parameter()]
            [object] $Value,

            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $StepName
        )

        if ($null -eq $Value) {
            return @()
        }

        $items = @()

        if ($Value -is [string]) {
            $items = @($Value)
        }
        elseif ($Value -is [System.Collections.IEnumerable]) {
            foreach ($v in $Value) {
                $items += $v
            }
        }
        else {
            throw [System.ArgumentException]::new(
                ("Workflow step '{0}' has invalid RequiresCapabilities value. Expected string or string array." -f $StepName),
                'Workflow'
            )
        }

        $normalized = @()
        foreach ($c in $items) {
            if ($null -eq $c) {
                continue
            }

            $s = ([string]$c).Trim()
            if ([string]::IsNullOrWhiteSpace($s)) {
                continue
            }

            # Keep convention aligned with Get-IdleProviderCapabilities:
            # - dot-separated segments
            # - no whitespace
            # - starts with a letter
            if ($s -notmatch '^[A-Za-z][A-Za-z0-9]*(\.[A-Za-z0-9]+)+$') {
                throw [System.ArgumentException]::new(
                    ("Workflow step '{0}' declares invalid capability '{1}'. Expected dot-separated segments like 'Identity.Read'." -f $StepName, $s),
                    'Workflow'
                )
            }

            $normalized += $s
        }

        return @($normalized | Sort-Object -Unique)
    }

    function Get-IdleProvidersFromMap {
        <#
        .SYNOPSIS
        Extracts provider instances from the -Providers argument.

        .DESCRIPTION
        The engine currently treats -Providers as a host-controlled bag of objects.
        This function extracts candidate provider objects for capability discovery.

        Supported shapes:
        - $null -> no providers
        - hashtable -> iterate values, ignoring known non-provider keys like 'StepRegistry'
        - PSCustomObject -> read public properties as provider entries

        This is intentionally conservative: only values that look like provider instances
        (non-null objects) are returned.
        #>
        [CmdletBinding()]
        param(
            [Parameter()]
            [AllowNull()]
            [object] $Providers
        )

        if ($null -eq $Providers) {
            return @()
        }

        $result = @()

        if ($Providers -is [hashtable]) {
            foreach ($k in $Providers.Keys) {
                # 'StepRegistry' is explicitly not a provider; it is a host extension point.
                if ([string]$k -eq 'StepRegistry') {
                    continue
                }

                $v = $Providers[$k]
                if ($null -ne $v) {
                    $result += $v
                }
            }

            return $result
        }

        # Allow an object bag (Providers.IdentityProvider, Providers.Directory, ...).
        $props = @($Providers.PSObject.Properties)
        foreach ($p in $props) {
            if ($p.MemberType -ne 'NoteProperty' -and $p.MemberType -ne 'Property') {
                continue
            }

            if ([string]$p.Name -eq 'StepRegistry') {
                continue
            }

            if ($null -ne $p.Value) {
                $result += $p.Value
            }
        }

        return $result
    }

    function Get-IdleAvailableCapabilities {
        <#
        .SYNOPSIS
        Builds a stable set of capabilities available from the provided providers.

        .DESCRIPTION
        Capabilities are discovered from each provider via Get-IdleProviderCapabilities.
        During the migration phase we allow minimal inference for legacy providers
        to avoid breaking existing demos/tests.

        The returned list is stable (sorted, unique).
        #>
        [CmdletBinding()]
        param(
            [Parameter()]
            [AllowNull()]
            [object] $Providers
        )

        $all = @()

        foreach ($p in @(Get-IdleProvidersFromMap -Providers $Providers)) {
            # AllowInference is a migration aid. Once the ecosystem advertises capabilities
            # explicitly, we can tighten this to explicit-only for maximum determinism.
            $all += @(Get-IdleProviderCapabilities -Provider $p -AllowInference)
        }

        return @($all | Sort-Object -Unique)
    }

    function Assert-IdlePlanCapabilitiesSatisfied {
        <#
        .SYNOPSIS
        Validates that all required step capabilities are available.

        .DESCRIPTION
        This is a fail-fast validation executed during planning.
        If one or more capabilities are missing, an ArgumentException is thrown with a
        deterministic error message that lists missing capabilities and affected steps.
        #>
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [ValidateNotNull()]
            [object[]] $Steps,

            [Parameter()]
            [AllowNull()]
            [object] $Providers
        )

        $required = @()
        $requiredByStep = @{}

        foreach ($s in @($Steps)) {
            $stepName = if ($s.PSObject.Properties.Name -contains 'Name') { [string]$s.Name } else { '<unknown>' }
            $caps = @()

            if ($s.PSObject.Properties.Name -contains 'RequiresCapabilities') {
                $caps = @($s.RequiresCapabilities)
            }

            if (@($caps).Count -gt 0) {
                $required += $caps
                $requiredByStep[$stepName] = @($caps)
            }
        }

        $required = @($required | Sort-Object -Unique)

        # Nothing required -> nothing to validate.
        if (@($required).Count -eq 0) {
            return
        }

        $available = Get-IdleAvailableCapabilities -Providers $Providers

        $missing = @()
        foreach ($c in $required) {
            if ($available -notcontains $c) {
                $missing += $c
            }
        }

        $missing = @($missing | Sort-Object -Unique)

        if (@($missing).Count -eq 0) {
            return
        }

        # Determine which steps are affected for better UX.
        $affectedSteps = @()
        foreach ($k in $requiredByStep.Keys) {
            $caps = @($requiredByStep[$k])
            foreach ($m in $missing) {
                if ($caps -contains $m) {
                    $affectedSteps += $k
                    break
                }
            }
        }

        $affectedSteps = @($affectedSteps | Sort-Object -Unique)

        $msg = @()
        $msg += "Plan cannot be built because required provider capabilities are missing."
        $msg += ("MissingCapabilities: {0}" -f ([string]::Join(', ', $missing)))
        $msg += ("AffectedSteps: {0}" -f ([string]::Join(', ', $affectedSteps)))
        $msg += ("AvailableCapabilities: {0}" -f ([string]::Join(', ', $available)))

        throw [System.ArgumentException]::new(([string]::Join(' ', $msg)), 'Providers')
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

        $requiresCaps = @()
        if ($s.ContainsKey('RequiresCapabilities')) {
            $requiresCaps = Normalize-IdleRequiredCapabilities -Value $s.RequiresCapabilities -StepName ([string]$s.Name)
        }

        $normalizedSteps += [pscustomobject]@{
            PSTypeName            = 'IdLE.PlanStep'
            Name                  = [string]$s.Name
            Type                  = [string]$s.Type
            Description           = if ($s.ContainsKey('Description')) { [string]$s.Description } else { '' }
            Condition             = $condition
            With                  = if ($s.ContainsKey('With')) { $s.With } else { @{} }
            RequiresCapabilities  = $requiresCaps
            Status                = $status
        }
    }

    # Attach steps to the plan after normalization.
    $plan.Steps = $normalizedSteps

    # Fail-fast capability validation (only if at least one step declares requirements).
    Assert-IdlePlanCapabilitiesSatisfied -Steps $plan.Steps -Providers $Providers

    return $plan
}

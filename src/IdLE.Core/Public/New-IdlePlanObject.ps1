function New-IdlePlanObject {
    <#
    .SYNOPSIS
    Builds a deterministic plan from a request and a workflow definition.

    .DESCRIPTION
    Loads and validates the workflow definition (PSD1) and creates a normalized plan object.
    This is a planning-only artifact. Execution is handled by Invoke-IdlePlanObject later.

    Planning responsibilities:
    - Create a data-only request snapshot for deterministic exports and auditing.
    - Normalize workflow steps to IdLE.PlanStep objects.
    - Evaluate step conditions during planning and mark steps as NotApplicable.
    - Validate required provider capabilities fail-fast (includes OnFailureSteps).

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
            [AllowNull()]
            [string] $Value
        )

        if ($null -eq $Value) {
            return $null
        }

        if ([string]::IsNullOrWhiteSpace($Value)) {
            return $null
        }

        return $Value
    }

    function Copy-IdleDataObject {
        <#
        .SYNOPSIS
        Creates a deep-ish, data-only copy of an object.

        .DESCRIPTION
        This helper is used to snapshot the request input so that the plan can be exported
        deterministically, without retaining references to the original live object.

        NOTE:
        This is intentionally conservative and only supports data-like objects:
        - Hashtable / OrderedDictionary
        - PSCustomObject / NoteProperties
        - Arrays/lists
        - Primitive types

        ScriptBlocks and other executable objects are rejected by upstream validation.
        #>
        [CmdletBinding()]
        param(
            [Parameter()]
            [AllowNull()]
            [object] $Value
        )

        if ($null -eq $Value) { return $null }

        if ($Value -is [System.Collections.IDictionary]) {
            $copy = [ordered]@{}
            foreach ($k in $Value.Keys) {
                $copy[$k] = Copy-IdleDataObject -Value $Value[$k]
            }
            return $copy
        }

        if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
            $arr = @()
            foreach ($item in $Value) {
                $arr += Copy-IdleDataObject -Value $item
            }
            return $arr
        }

        $props = @($Value.PSObject.Properties | Where-Object MemberType -in @('NoteProperty', 'Property'))
        if ($null -ne $props -and @($props).Count -gt 0) {
            $o = [ordered]@{}
            foreach ($p in $props) {
                $o[$p.Name] = Copy-IdleDataObject -Value $p.Value
            }
            return [pscustomobject]$o
        }

        return $Value
    }

    function Get-IdleOptionalPropertyValue {
        <#
        .SYNOPSIS
        Safely reads an optional property from an object.

        .DESCRIPTION
        Works with:
        - IDictionary (hashtables / ordered dictionaries)
        - PSCustomObject / objects with note properties

        Returns $null when the property does not exist.
        Uses Get-Member to avoid PropertyNotFoundException in strict mode.
        #>
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [AllowNull()]
            [object] $Object,

            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $Name
        )

        if ($null -eq $Object) {
            return $null
        }

        if ($Object -is [System.Collections.IDictionary]) {
            if ($Object.ContainsKey($Name)) {
                return $Object[$Name]
            }
            return $null
        }

        $m = $Object | Get-Member -Name $Name -MemberType NoteProperty,Property -ErrorAction SilentlyContinue
        if ($null -eq $m) {
            return $null
        }

        return $Object.$Name
    }

    function Normalize-IdleRequiredCapabilities {
        <#
        .SYNOPSIS
        Normalizes the optional RequiresCapabilities key from a workflow step.

        .DESCRIPTION
        Supported shapes:
        - missing / $null -> empty list
        - string -> single capability
        - array/enumerable of strings -> list of capabilities

        The output is a stable, sorted, unique string array.
        #>
        [CmdletBinding()]
        param(
            [Parameter()]
            [AllowNull()]
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
        Supports both:
        - hashtable map: @{ Name = <providerObject>; ... }
        - array/list: @( <providerObject>, ... )

        Returns an array of provider objects.
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

        if ($Providers -is [System.Collections.IDictionary]) {
            $items = @()
            foreach ($k in $Providers.Keys) {
                $items += $Providers[$k]
            }
            return @($items)
        }

        if ($Providers -is [System.Collections.IEnumerable] -and $Providers -isnot [string]) {
            $items = @()
            foreach ($p in $Providers) {
                $items += $p
            }
            return @($items)
        }

        return @($Providers)
    }

    function Get-IdleProviderCapabilities {
        <#
        .SYNOPSIS
        Gets the capability list advertised by a provider.

        .DESCRIPTION
        Providers are expected to expose a GetCapabilities() method.
        If not present, the provider is treated as advertising no capabilities.
        #>
        [CmdletBinding()]
        param(
            [Parameter()]
            [AllowNull()]
            [object] $Provider
        )

        if ($null -eq $Provider) {
            return @()
        }

        if ($Provider.PSObject.Methods.Name -contains 'GetCapabilities') {
            $caps = $Provider.GetCapabilities()
            if ($null -eq $caps) {
                return @()
            }
            return @($caps | Where-Object { $null -ne $_ } | ForEach-Object { ([string]$_).Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
        }

        return @()
    }

    function Get-IdleAvailableCapabilities {
        <#
        .SYNOPSIS
        Aggregates capabilities from all providers.
        #>
        [CmdletBinding()]
        param(
            [Parameter()]
            [AllowNull()]
            [object] $Providers
        )

        $providerInstances = @(Get-IdleProvidersFromMap -Providers $Providers)

        $caps = @()
        foreach ($p in $providerInstances) {
            $caps += @(Get-IdleProviderCapabilities -Provider $p)
        }

        return @($caps | Sort-Object -Unique)
    }

    function Assert-IdlePlanCapabilitiesSatisfied {
        <#
        .SYNOPSIS
        Validates that all required step capabilities are available.

        .DESCRIPTION
        Fail-fast validation executed during planning.
        If one or more capabilities are missing, an ArgumentException is thrown with a
        deterministic error message listing missing capabilities and affected steps.
        #>
        [CmdletBinding()]
        param(
            [Parameter()]
            [AllowNull()]
            [object[]] $Steps,

            [Parameter()]
            [AllowNull()]
            [object] $Providers
        )

        if ($null -eq $Steps -or @($Steps).Count -eq 0) {
            return
        }

        $required = @()
        $requiredByStep = [ordered]@{}

        foreach ($s in @($Steps)) {
            if ($null -eq $s) {
                continue
            }

            $stepName = Get-IdleOptionalPropertyValue -Object $s -Name 'Name'
            if ($null -eq $stepName -or [string]::IsNullOrWhiteSpace([string]$stepName)) {
                $stepName = '<UnnamedStep>'
            }

            $capsRaw = Get-IdleOptionalPropertyValue -Object $s -Name 'RequiresCapabilities'
            $caps = if ($null -eq $capsRaw) { @() } else { @($capsRaw) }

            if (@($caps).Count -gt 0) {
                $required += $caps
                $requiredByStep[$stepName] = @($caps)
            }
        }

        $required = @($required | Sort-Object -Unique)
        if (@($required).Count -eq 0) {
            return
        }

        $available = @(Get-IdleAvailableCapabilities -Providers $Providers)

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

        $affectedSteps = @()
        foreach ($k in $requiredByStep.Keys) {
            $capsForStep = @($requiredByStep[$k])
            foreach ($m in $missing) {
                if ($capsForStep -contains $m) {
                    $affectedSteps += $k
                    break
                }
            }
        }

        $affectedSteps = @($affectedSteps | Sort-Object -Unique)

        $msg = @()
        $msg += "Plan cannot be built because required provider capabilities are missing."
        $msg += ("MissingCapabilities: {0}" -f ([string]::Join(', ', @($missing))))
        $msg += ("AffectedSteps: {0}" -f ([string]::Join(', ', @($affectedSteps))))
        $msg += ("AvailableCapabilities: {0}" -f ([string]::Join(', ', @($available))))

        throw [System.ArgumentException]::new(([string]::Join(' ', $msg)), 'Providers')
    }

    function Test-IdleWorkflowStepKey {
        <#
        .SYNOPSIS
        Checks whether a workflow step contains a given key.
        #>
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [ValidateNotNull()]
            [object] $Step,

            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $Key
        )

        if ($Step -is [System.Collections.IDictionary]) {
            return $Step.ContainsKey($Key)
        }

        $m = $Step | Get-Member -Name $Key -MemberType NoteProperty,Property -ErrorAction SilentlyContinue
        return ($null -ne $m)
    }

    function Get-IdleWorkflowStepValue {
        <#
        .SYNOPSIS
        Gets a value from a workflow step by key.
        #>
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [ValidateNotNull()]
            [object] $Step,

            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $Key
        )

        if ($Step -is [System.Collections.IDictionary]) {
            return $Step[$Key]
        }

        return $Step.$Key
    }

    function Normalize-IdleWorkflowSteps {
        <#
        .SYNOPSIS
        Normalizes workflow steps into IdLE.PlanStep objects.

        .DESCRIPTION
        Evaluates Condition during planning and sets Status = Planned / NotApplicable.

        IMPORTANT:
        WorkflowSteps is optional and may be null or empty. A workflow is allowed to omit
        OnFailureSteps entirely. Therefore we must not mark this parameter as Mandatory.
        #>
        [CmdletBinding()]
        param(
            [Parameter()]
            [AllowNull()]
            [object[]] $WorkflowSteps,

            [Parameter(Mandatory)]
            [ValidateNotNull()]
            [object] $PlanningContext
        )

        if ($null -eq $WorkflowSteps -or @($WorkflowSteps).Count -eq 0) {
            return @()
        }

        $normalizedSteps = @()

        foreach ($s in @($WorkflowSteps)) {
            $stepName = if (Test-IdleWorkflowStepKey -Step $s -Key 'Name') {
                [string](Get-IdleWorkflowStepValue -Step $s -Key 'Name')
            }
            else {
                ''
            }

            if ([string]::IsNullOrWhiteSpace($stepName)) {
                throw [System.ArgumentException]::new('Workflow step is missing required key "Name".', 'Workflow')
            }

            $stepType = if (Test-IdleWorkflowStepKey -Step $s -Key 'Type') {
                [string](Get-IdleWorkflowStepValue -Step $s -Key 'Type')
            }
            else {
                ''
            }

            if ([string]::IsNullOrWhiteSpace($stepType)) {
                throw [System.ArgumentException]::new(("Workflow step '{0}' is missing required key 'Type'." -f $stepName), 'Workflow')
            }

            if (Test-IdleWorkflowStepKey -Step $s -Key 'When') {
                throw [System.ArgumentException]::new(
                    ("Workflow step '{0}' uses key 'When'. 'When' has been renamed to 'Condition'. Please update the workflow definition." -f $stepName),
                    'Workflow'
                )
            }

            $condition = if (Test-IdleWorkflowStepKey -Step $s -Key 'Condition') {
                Get-IdleWorkflowStepValue -Step $s -Key 'Condition'
            }
            else {
                $null
            }

            $status = 'Planned'
            if ($null -ne $condition) {
                $schemaErrors = Test-IdleConditionSchema -Condition $condition -StepName $stepName
                if (@($schemaErrors).Count -gt 0) {
                    throw [System.ArgumentException]::new(
                        ("Invalid Condition on step '{0}': {1}" -f $stepName, ([string]::Join(' ', @($schemaErrors)))),
                        'Workflow'
                    )
                }

                $isApplicable = Test-IdleCondition -Condition $condition -Context $PlanningContext
                if (-not $isApplicable) {
                    $status = 'NotApplicable'
                }
            }

            $requiresCaps = @()
            if (Test-IdleWorkflowStepKey -Step $s -Key 'RequiresCapabilities') {
                $requiresCaps = Normalize-IdleRequiredCapabilities -Value (Get-IdleWorkflowStepValue -Step $s -Key 'RequiresCapabilities') -StepName $stepName
            }

            $description = if (Test-IdleWorkflowStepKey -Step $s -Key 'Description') {
                [string](Get-IdleWorkflowStepValue -Step $s -Key 'Description')
            }
            else {
                ''
            }

            $with = if (Test-IdleWorkflowStepKey -Step $s -Key 'With') {
                Copy-IdleDataObject -Value (Get-IdleWorkflowStepValue -Step $s -Key 'With')
            }
            else {
                @{}
            }

            $normalizedSteps += [pscustomobject]@{
                PSTypeName           = 'IdLE.PlanStep'
                Name                 = $stepName
                Type                 = $stepType
                Description          = $description
                Condition            = Copy-IdleDataObject -Value $condition
                With                 = $with
                RequiresCapabilities = $requiresCaps
                Status               = $status
            }
        }

        # IMPORTANT:
        # Returning an empty array variable can produce no pipeline output, resulting in $null on assignment.
        # Force a stable array output shape.
        return @($normalizedSteps)
    }

    # Ensure required request properties exist without hard-typing the request class.
    $reqProps = $Request.PSObject.Properties.Name
    if ($reqProps -notcontains 'LifecycleEvent') {
        throw [System.ArgumentException]::new("Request object must contain property 'LifecycleEvent'.", 'Request')
    }
    if ($reqProps -notcontains 'CorrelationId') {
        throw [System.ArgumentException]::new("Request object must contain property 'CorrelationId'.", 'Request')
    }

    # Create a data-only snapshot of the incoming request for deterministic exports.
    $requestSnapshot = [pscustomobject]@{
        PSTypeName     = 'IdLE.LifecycleRequestSnapshot'
        LifecycleEvent = ConvertTo-NullIfEmptyString -Value ([string]$Request.LifecycleEvent)
        CorrelationId  = ConvertTo-NullIfEmptyString -Value ([string]$Request.CorrelationId)
        Actor          = if ($reqProps -contains 'Actor') { ConvertTo-NullIfEmptyString -Value ([string]$Request.Actor) } else { $null }
        IdentityKeys   = if ($reqProps -contains 'IdentityKeys') { Copy-IdleDataObject -Value $Request.IdentityKeys } else { $null }
        DesiredState   = if ($reqProps -contains 'DesiredState') { Copy-IdleDataObject -Value $Request.DesiredState } else { $null }
        Changes        = if ($reqProps -contains 'Changes') { Copy-IdleDataObject -Value $Request.Changes } else { $null }
    }

    # Validate workflow and ensure it matches the request's LifecycleEvent.
    $workflow = Test-IdleWorkflowDefinitionObject -WorkflowPath $WorkflowPath -Request $Request

    # Create the plan object (planning artifact).
    $plan = [pscustomobject]@{
        PSTypeName     = 'IdLE.Plan'
        WorkflowName   = [string]$workflow.Name
        LifecycleEvent = [string]$workflow.LifecycleEvent
        CorrelationId  = [string]$requestSnapshot.CorrelationId
        Request        = $requestSnapshot
        Actor          = $requestSnapshot.Actor
        CreatedUtc     = [DateTime]::UtcNow

        Steps          = @()
        OnFailureSteps = @()

        Actions        = @()
        Warnings       = @()
        Providers      = $Providers
    }

    # Build a planning context for condition evaluation.
    $planningContext = [pscustomobject]@{
        Plan     = $plan
        Request  = $Request
        Workflow = $workflow
    }

    $workflowOnFailureSteps = Get-IdleOptionalPropertyValue -Object $workflow -Name 'OnFailureSteps'

    # Normalize primary and OnFailure steps.
    # IMPORTANT:
    # Normalize-IdleWorkflowSteps may return an empty array that would otherwise collapse to $null on assignment.
    $plan.Steps = @(Normalize-IdleWorkflowSteps -WorkflowSteps $workflow.Steps -PlanningContext $planningContext)
    $plan.OnFailureSteps = @(Normalize-IdleWorkflowSteps -WorkflowSteps $workflowOnFailureSteps -PlanningContext $planningContext)

    # Fail-fast capability validation (includes OnFailureSteps).
    $allStepsForCapabilities = @()
    $allStepsForCapabilities += @($plan.Steps)
    $allStepsForCapabilities += @($plan.OnFailureSteps)

    Assert-IdlePlanCapabilitiesSatisfied -Steps $allStepsForCapabilities -Providers $Providers

    return $plan
}

function Invoke-IdlePlanObject {
    <#
    .SYNOPSIS
    Executes an IdLE plan object and returns a deterministic execution result.

    .DESCRIPTION
    Executes steps in order, emits structured events, and returns a stable execution result.

    Provider resolution:
    - If -Providers is supplied, it is used for execution.
    - If -Providers is not supplied (null), Plan.Providers is used if available.
    - If neither is present, execution fails early with a clear error message.

    Security:
    - ScriptBlocks are rejected in plan and providers.
    - The returned execution result is an output boundary: Providers are redacted.

    .PARAMETER Plan
    Plan object created by New-IdlePlanObject.

    .PARAMETER Providers
    Provider registry/collection passed through to execution.
    If omitted and Plan.Providers exists, Plan.Providers will be used.
    If supplied, overrides Plan.Providers.

    .PARAMETER EventSink
    Optional external event sink object. Must provide a WriteEvent(event) method.

    .PARAMETER ExecutionOptions
    Optional host-owned execution options. Supports retry profile configuration.
    Must be a hashtable with optional keys: RetryProfiles, DefaultRetryProfile.

    .OUTPUTS
    PSCustomObject (PSTypeName: IdLE.ExecutionResult)

    .EXAMPLE
    $result = Invoke-IdlePlanObject -Plan $plan -Providers $providers

    Executes a plan with the specified provider registry and returns an execution result.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Plan,

        [Parameter()]
        [AllowNull()]
        [object] $Providers,

        [Parameter()]
        [AllowNull()]
        [object] $EventSink,

        [Parameter()]
        [AllowNull()]
        [hashtable] $ExecutionOptions
    )

    $planPropNames = @($Plan.PSObject.Properties.Name)

    $request = if ($planPropNames -contains 'Request') { $Plan.Request } else { $null }
    $requestPropNames = if ($null -ne $request) { @($request.PSObject.Properties.Name) } else { @() }

    $corr = if ($null -ne $request -and $requestPropNames -contains 'CorrelationId') {
        $request.CorrelationId
    }
    else {
        if ($planPropNames -contains 'CorrelationId') { $Plan.CorrelationId } else { $null }
    }

    $actor = if ($null -ne $request -and $requestPropNames -contains 'Actor') {
        $request.Actor
    }
    else {
        if ($planPropNames -contains 'Actor') { $Plan.Actor } else { $null }
    }

    $events = [System.Collections.Generic.List[object]]::new()

    # Host may pass an external sink. If none is provided, we still buffer events internally.
    $engineEventSink = New-IdleEventSink -CorrelationId $corr -Actor $actor -ExternalEventSink $EventSink -EventBuffer $events

    # Enforce data-only boundary: reject ScriptBlocks in untrusted inputs.
    # Special-case: for auth session acquisition options, throw a contextualized error message.
    $planSteps = if ($planPropNames -contains 'Steps') { $Plan.Steps } else { $null }
    if ($null -ne $planSteps -and ($planSteps -is [System.Collections.IEnumerable]) -and ($planSteps -isnot [string])) {
        $i = 0
        foreach ($step in $planSteps) {
            $stepType = [string](Get-IdlePropertyValue -Object $step -Name 'Type')
            if ($stepType -eq 'IdLE.Step.AcquireAuthSession') {
                $with = Get-IdlePropertyValue -Object $step -Name 'With'
                $options = $null
                if ($null -ne $with) {
                    if ($with -is [System.Collections.IDictionary]) {
                        if ($with.Contains('Options')) { $options = $with['Options'] }
                    }
                    else {
                        if ($with.PSObject.Properties.Name -contains 'Options') { $options = $with.Options }
                    }
                }

                Assert-IdleNoScriptBlockInAuthSessionOptions -InputObject $options -Path "Plan.Steps[$i].With.Options"
            }

            $i++
        }
    }

    Assert-IdleNoScriptBlock -InputObject $Plan -Path 'Plan'

    # Resolve effective providers: explicit -Providers parameter takes precedence, otherwise use Plan.Providers.
    # This allows the common workflow: build plan with providers once, execute without re-supplying them.
    $effectiveProviders = $Providers
    if ($null -eq $effectiveProviders) {
        if ($planPropNames -contains 'Providers') {
            $planProviders = $Plan.Providers
            # Accept both IDictionary (hashtables) and PSCustomObject-shaped provider registries
            if ($null -ne $planProviders) {
                $isValidProvider = ($planProviders -is [System.Collections.IDictionary]) -or 
                ($planProviders.PSObject -and $planProviders.PSObject.Properties)
                if ($isValidProvider) {
                    $effectiveProviders = $planProviders
                }
            }
        }
    }

    # Early validation: fail with a clear message if no providers are available.
    if ($null -eq $effectiveProviders) {
        throw [System.InvalidOperationException]::new(
            'Providers are required. Provide -Providers to Invoke-IdlePlan or build the plan with Providers.'
        )
    }

    Assert-IdleNoScriptBlock -InputObject $effectiveProviders -Path 'Providers'

    # Validate ExecutionOptions
    Assert-IdleExecutionOptions -ExecutionOptions $ExecutionOptions

    # StepRegistry is constructed via helper to ensure built-in steps and host-provided steps can co-exist.
    $stepRegistry = Get-IdleStepRegistry -Providers $effectiveProviders

    $context = [pscustomobject]@{
        PSTypeName = 'IdLE.ExecutionContext'
        Plan       = $Plan
        Providers  = $effectiveProviders
        EventSink  = $engineEventSink
    }

    # Expose common run metadata on the execution context so providers can enrich session acquisition requests
    # without having to parse the plan structure themselves.
    $null = $context | Add-Member -MemberType NoteProperty -Name CorrelationId -Value $corr -Force
    $null = $context | Add-Member -MemberType NoteProperty -Name Actor -Value $actor -Force

    # Session acquisition boundary:
    # - Providers MUST NOT implement their own authentication flows.
    # - The host supplies an AuthSessionBroker in Providers.AuthSessionBroker.
    # - Options must be data-only (no ScriptBlocks).
    $null = $context | Add-Member -MemberType ScriptMethod -Name AcquireAuthSession -Value {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $Name,

            [Parameter()]
            [AllowNull()]
            [hashtable] $Options
        )

        $providers = $this.Providers
        $broker = $null

        if ($providers -is [System.Collections.IDictionary]) {
            if ($providers.Contains('AuthSessionBroker')) {
                $broker = $providers['AuthSessionBroker']
            }
        }
        else {
            if ($null -ne $providers -and $providers.PSObject.Properties.Name -contains 'AuthSessionBroker') {
                $broker = $providers.AuthSessionBroker
            }
        }

        if ($null -eq $broker) {
            throw [System.InvalidOperationException]::new(
                'No AuthSessionBroker configured. Provide Providers.AuthSessionBroker to acquire auth sessions during execution.'
            )
        }

        if ($broker.PSObject.Methods.Name -notcontains 'AcquireAuthSession') {
            throw [System.InvalidOperationException]::new(
                'AuthSessionBroker must provide an AcquireAuthSession(Name, Options) method.'
            )
        }

        $normalizedOptions = if ($null -eq $Options) { @{} } else { $Options }
        Assert-IdleNoScriptBlockInAuthSessionOptions -InputObject $normalizedOptions -Path 'AuthSessionOptions'

        # Copy options to avoid mutating caller-owned hashtables.
        $optionsCopy = Copy-IdleDataObject -Value $normalizedOptions

        if ($null -ne $this.CorrelationId) { $optionsCopy['CorrelationId'] = $this.CorrelationId }
        if ($null -ne $this.Actor) { $optionsCopy['Actor'] = $this.Actor }

        return $broker.AcquireAuthSession($Name, $optionsCopy)
    } -Force

    # Fail-fast security validation: Check if AuthSessionBroker is required but missing.
    # AcquireAuthSession steps require an AuthSessionBroker to be present in Providers.
    # Skip NotApplicable steps, as they won't be executed and don't require the broker.
    $requiresAuthBroker = $false
    $steps = if ($planPropNames -contains 'Steps') { $Plan.Steps } else { @() }
    foreach ($step in $steps) {
        if ($null -eq $step) { continue }

        $stepType = $null
        $stepStatus = $null
        if ($step -is [System.Collections.IDictionary]) {
            if ($step.Contains('Type')) {
                $stepType = $step['Type']
            }
            if ($step.Contains('Status')) {
                $stepStatus = $step['Status']
            }
        }
        else {
            $stepPropNames = @($step.PSObject.Properties.Name)
            $stepType = if ($stepPropNames -contains 'Type') { $step.Type } else { $null }
            $stepStatus = if ($stepPropNames -contains 'Status') { $step.Status } else { $null }
        }

        if ($stepType -eq 'IdLE.Step.AcquireAuthSession' -and $stepStatus -ne 'NotApplicable') {
            $requiresAuthBroker = $true
            break
        }
    }

    if ($requiresAuthBroker) {
        $broker = $null
        if ($effectiveProviders -is [System.Collections.IDictionary]) {
            if ($effectiveProviders.Contains('AuthSessionBroker')) {
                $broker = $effectiveProviders['AuthSessionBroker']
            }
        }
        else {
            if ($null -ne $effectiveProviders -and $effectiveProviders.PSObject.Properties.Name -contains 'AuthSessionBroker') {
                $broker = $effectiveProviders.AuthSessionBroker
            }
        }

        if ($null -eq $broker) {
            throw [System.InvalidOperationException]::new(
                'AuthSessionBroker is required but not configured. One or more steps require auth session acquisition. Provide Providers.AuthSessionBroker to proceed.'
            )
        }
    }

    $context.EventSink.WriteEvent(
        'RunStarted',
        'Plan execution started.',
        $null,
        @{
            CorrelationId = $corr
            Actor         = $actor
            StepCount     = @($Plan.Steps).Count
        }
    )

    $failed = $false
    $blocked = $false
    $stepResults = @()

    # Precondition evaluation context: includes Plan and Request for condition DSL path resolution.
    $preconditionContext = @{
        Plan    = $Plan
        Request = $request
    }

    $i = 0
    foreach ($step in $Plan.Steps) {

        if ($null -eq $step) {
            continue
        }

        $stepName = [string](Get-IdlePropertyValue -Object $step -Name 'Name')
        if ($null -eq $stepName) { $stepName = '' }

        $stepType = Get-IdlePropertyValue -Object $step -Name 'Type'
        $stepWith = Get-IdlePropertyValue -Object $step -Name 'With'
        $stepStatus = [string](Get-IdlePropertyValue -Object $step -Name 'Status')
        if ($null -eq $stepStatus) { $stepStatus = '' }

        # Conditions are evaluated during planning and represented as Step.Status.
        if ($stepStatus -eq 'NotApplicable') {

            $stepResults += [pscustomobject]@{
                PSTypeName = 'IdLE.StepResult'
                Name       = $stepName
                Type       = $stepType
                Status     = 'NotApplicable'
                Attempts   = 1
            }

            $context.EventSink.WriteEvent(
                'StepNotApplicable',
                "Step '$stepName' not applicable (condition not met).",
                $stepName,
                @{
                    StepType = $stepType
                    Index    = $i
                }
            )

            $i++
            continue
        }

        # Runtime Precondition: evaluated immediately before step execution (online, not planning-time).
        # Blocked = policy/precondition gate (does not trigger OnFailureSteps). Stops execution.
        # Fail    = treated as a technical failure (triggers OnFailureSteps). Stops execution.
        # Continue = emits events but skips the step and continues to the next step.
        # Non-IDictionary precondition nodes are treated as precondition failures (fail closed).
        $stepPrecondition = Get-IdlePropertyValue -Object $step -Name 'Precondition'

        # Set Request.Context.Current alias for step-relative path resolution in preconditions.
        # Resolved from Step.With.Provider + Step.With.AuthSessionName (or 'Default').
        # Scoped to the precondition evaluation; cleaned up immediately after.
        $currentContextSet = $false
        if ($null -ne $stepPrecondition -and $null -ne $request -and $null -ne $request.Context -and $request.Context -is [System.Collections.IDictionary]) {
            $currentProviderAlias = $null
            $currentAuthKey = 'Default'
            if ($null -ne $stepWith) {
                if ($stepWith -is [System.Collections.IDictionary]) {
                    if ($stepWith.Contains('Provider') -and -not [string]::IsNullOrWhiteSpace([string]$stepWith['Provider'])) {
                        $currentProviderAlias = [string]$stepWith['Provider']
                    }
                    if ($stepWith.Contains('AuthSessionName') -and -not [string]::IsNullOrWhiteSpace([string]$stepWith['AuthSessionName'])) {
                        $currentAuthKey = [string]$stepWith['AuthSessionName']
                    }
                }
                elseif ($stepWith.PSObject.Properties.Name -contains 'Provider') {
                    $pVal = $stepWith.Provider
                    if (-not [string]::IsNullOrWhiteSpace([string]$pVal)) { $currentProviderAlias = [string]$pVal }
                    $aVal = if ($stepWith.PSObject.Properties.Name -contains 'AuthSessionName') { $stepWith.AuthSessionName } else { $null }
                    if (-not [string]::IsNullOrWhiteSpace([string]$aVal)) { $currentAuthKey = [string]$aVal }
                }
            }

            $currentContextValue = $null
            if (-not [string]::IsNullOrWhiteSpace($currentProviderAlias)) {
                $providersNode = if ($request.Context.Contains('Providers')) { $request.Context['Providers'] } else { $null }
                if ($null -ne $providersNode -and $providersNode -is [System.Collections.IDictionary] -and $providersNode.Contains($currentProviderAlias)) {
                    $providerNode = $providersNode[$currentProviderAlias]
                    if ($null -ne $providerNode -and $providerNode -is [System.Collections.IDictionary] -and $providerNode.Contains($currentAuthKey)) {
                        $currentContextValue = $providerNode[$currentAuthKey]
                    }
                }
            }

            $request.Context['Current'] = $currentContextValue
            $currentContextSet = $true
        }

        if ($null -ne $stepPrecondition) {
            $preconditionPassed = $true
            if ($stepPrecondition -isnot [System.Collections.IDictionary]) {
                # Fail closed: a malformed or unexpected node type is treated as a failed precondition.
                $preconditionPassed = $false
            }
            else {
                # Validate that all non-Exists paths exist at execution time.
                # Exists operator paths are excluded because Exists semantics intentionally allow missing paths.
                Assert-IdleConditionPathsResolvable -Condition ([hashtable]$stepPrecondition) -Context $preconditionContext -StepName $stepName -Source 'Precondition' -ExcludeExistsOperatorPaths
                if (-not (Test-IdleCondition -Condition ([hashtable]$stepPrecondition) -Context $preconditionContext)) {
                    $preconditionPassed = $false
                }
            }

            if (-not $preconditionPassed) {
                $onPreconditionFalse = [string](Get-IdlePropertyValue -Object $step -Name 'OnPreconditionFalse')
                if ([string]::IsNullOrWhiteSpace($onPreconditionFalse)) { $onPreconditionFalse = 'Blocked' }

                # Always emit StepPreconditionFailed for engine observability.
                $context.EventSink.WriteEvent(
                    'StepPreconditionFailed',
                    "Step '$stepName' precondition check failed.",
                    $stepName,
                    @{
                        StepType            = $stepType
                        Index               = $i
                        OnPreconditionFalse = $onPreconditionFalse
                    }
                )

                # Emit the caller-configured PreconditionEvent if present.
                $pcEvt = Get-IdlePropertyValue -Object $step -Name 'PreconditionEvent'
                if ($null -ne $pcEvt) {
                    $pcEvtType = [string](Get-IdlePropertyValue -Object $pcEvt -Name 'Type')
                    $pcEvtMsg = [string](Get-IdlePropertyValue -Object $pcEvt -Name 'Message')
                    $pcEvtData = Get-IdlePropertyValue -Object $pcEvt -Name 'Data'
                    # PreconditionEvent.Data is validated as a hashtable at planning time and
                    # stored via Copy-IdleDataObject, so it will be a hashtable (IDictionary) here.
                    $pcEvtDataHt = if ($pcEvtData -is [System.Collections.IDictionary]) { [hashtable]$pcEvtData } else { $null }
                    $context.EventSink.WriteEvent($pcEvtType, $pcEvtMsg, $stepName, $pcEvtDataHt)
                }

                if ($onPreconditionFalse -eq 'Fail') {
                    $failed = $true
                    $stepResults += [pscustomobject]@{
                        PSTypeName = 'IdLE.StepResult'
                        Name       = $stepName
                        Type       = $stepType
                        Status     = 'Failed'
                        Error      = 'Precondition check failed.'
                        Attempts   = 0
                    }
                    $context.EventSink.WriteEvent(
                        'StepFailed',
                        "Step '$stepName' failed (precondition check failed).",
                        $stepName,
                        @{
                            StepType = $stepType
                            Index    = $i
                            Error    = 'Precondition check failed.'
                        }
                    )
                }
                elseif ($onPreconditionFalse -eq 'Continue') {
                    # Emit events and skip the step; continue to subsequent steps.
                    $stepResults += [pscustomobject]@{
                        PSTypeName = 'IdLE.StepResult'
                        Name       = $stepName
                        Type       = $stepType
                        Status     = 'PreconditionSkipped'
                        Attempts   = 0
                    }
                    $i++
                    # Clean up the Current alias before continuing to the next step.
                    if ($currentContextSet -and $null -ne $request -and $null -ne $request.Context -and $request.Context -is [System.Collections.IDictionary]) {
                        $null = $request.Context.Remove('Current')
                    }
                    continue
                }
                else {
                    # Default: Blocked. Does not trigger OnFailureSteps.
                    $blocked = $true
                    $stepResults += [pscustomobject]@{
                        PSTypeName = 'IdLE.StepResult'
                        Name       = $stepName
                        Type       = $stepType
                        Status     = 'Blocked'
                        Attempts   = 0
                    }
                    $context.EventSink.WriteEvent(
                        'StepBlocked',
                        "Step '$stepName' blocked (precondition check failed).",
                        $stepName,
                        @{
                            StepType = $stepType
                            Index    = $i
                        }
                    )
                }

                break
            }
        }

        # Stop processing if a precondition failure was handled above.
        if ($failed -or $blocked) { break }

        # Clean up the Current alias after precondition evaluation.
        if ($currentContextSet -and $null -ne $request -and $null -ne $request.Context -and $request.Context -is [System.Collections.IDictionary]) {
            $null = $request.Context.Remove('Current')
        }

        $context.EventSink.WriteEvent(
            'StepStarted',
            "Step '$stepName' started.",
            $stepName,
            @{
                StepType = $stepType
                Index    = $i
            }
        )

        try {
            $impl = Resolve-IdleStepHandler -StepType ([string]$stepType) -StepRegistry $stepRegistry

            $supportedParams = Get-IdleCommandParameterNames -Handler $impl

            $invokeParams = @{}

            # Backwards compatibility: pass -Context only when the handler supports it.
            if ($supportedParams.Contains('Context')) {
                $invokeParams.Context = $context
            }

            if ($null -ne $stepWith -and $supportedParams.Contains('With')) {
                $invokeParams.With = $stepWith
            }

            if ($supportedParams.Contains('Step')) {
                $invokeParams.Step = $step
            }

            # Safe-by-default transient retries:
            # - Only retries if the thrown exception is explicitly marked transient.
            # - Emits 'StepRetrying' events and uses deterministic jitter/backoff.
            # - Retry parameters resolved from ExecutionOptions if provided.
            $retrySeed = "$corr|$stepType|$stepName|$i"
            $retryParams = Resolve-IdleStepRetryParameters -Step $step -ExecutionOptions $ExecutionOptions
            $retry = Invoke-IdleWithRetry `
                -Operation { & $impl @invokeParams } `
                -MaxAttempts $retryParams.MaxAttempts `
                -InitialDelayMilliseconds $retryParams.InitialDelayMilliseconds `
                -BackoffFactor $retryParams.BackoffFactor `
                -MaxDelayMilliseconds $retryParams.MaxDelayMilliseconds `
                -JitterRatio $retryParams.JitterRatio `
                -EventSink $context.EventSink `
                -StepName $stepName `
                -OperationName 'StepExecution' `
                -DeterministicSeed $retrySeed

            $result = $retry.Value
            $attempts = [int]$retry.Attempts

            if ($null -eq $result) {
                $result = [pscustomobject]@{
                    PSTypeName = 'IdLE.StepResult'
                    Name       = $stepName
                    Type       = $stepType
                    Status     = 'Completed'
                    Attempts   = $attempts
                }
            }
            else {
                # Normalize result to include Attempts for observability (non-breaking).
                if ($result.PSObject.Properties.Name -notcontains 'Attempts') {
                    $null = $result | Add-Member -MemberType NoteProperty -Name Attempts -Value $attempts -Force
                }
            }

            $stepResults += $result

            if ($result.Status -eq 'Failed') {
                $failed = $true

                $context.EventSink.WriteEvent(
                    'StepFailed',
                    "Step '$stepName' failed.",
                    $stepName,
                    @{
                        StepType = $stepType
                        Index    = $i
                        Error    = $result.Error
                    }
                )

                break
            }

            $context.EventSink.WriteEvent(
                'StepCompleted',
                "Step '$stepName' completed.",
                $stepName,
                @{
                    StepType = $stepType
                    Index    = $i
                }
            )
        }
        catch {
            $failed = $true
            $err = $_

            $stepResults += [pscustomobject]@{
                PSTypeName = 'IdLE.StepResult'
                Name       = $stepName
                Type       = $stepType
                Status     = 'Failed'
                Error      = $err.Exception.Message
                Attempts   = 1
            }

            $context.EventSink.WriteEvent(
                'StepFailed',
                "Step '$stepName' failed.",
                $stepName,
                @{
                    StepType = $stepType
                    Index    = $i
                    Error    = $err.Exception.Message
                }
            )

            break
        }

        $i++
    }

    $runStatus = if ($blocked) { 'Blocked' } elseif ($failed) { 'Failed' } else { 'Completed' }

    # Public result contract: the OnFailure section is always present.
    $onFailure = [pscustomobject]@{
        PSTypeName = 'IdLE.OnFailureExecutionResult'
        Status     = 'NotRun'
        Steps      = [object[]]@()
    }

    $planOnFailureSteps = @()
    if ($planPropNames -contains 'OnFailureSteps') {
        # Treat nulls as empty deterministically.
        $planOnFailureSteps = @($Plan.OnFailureSteps) | Where-Object { $null -ne $_ }
    }

    # OnFailureSteps run only for genuine failures, NOT for Blocked outcomes (policy gates).
    if ($failed -and -not $blocked -and @($planOnFailureSteps).Count -gt 0) {
        $context.EventSink.WriteEvent(
            'OnFailureStarted',
            'Executing OnFailureSteps (best effort).',
            $null,
            @{
                OnFailureStepCount = @($planOnFailureSteps).Count
            }
        )

        $onFailureHadFailures = $false
        $onFailureStepResults = @()

        $j = 0
        foreach ($ofStep in @($planOnFailureSteps)) {

            if ($null -eq $ofStep) {
                $j++
                continue
            }

            $ofPropNames = @($ofStep.PSObject.Properties.Name)
            $ofName = if ($ofPropNames -contains 'Name') { [string]$ofStep.Name } else { '' }
            $ofType = if ($ofPropNames -contains 'Type') { $ofStep.Type } else { $null }
            $ofWith = if ($ofPropNames -contains 'With') { $ofStep.With } else { $null }
            $ofStatus = if ($ofPropNames -contains 'Status') { [string]$ofStep.Status } else { '' }

            # Conditions for OnFailure steps are evaluated during planning as well.
            if ($ofStatus -eq 'NotApplicable') {

                $onFailureStepResults += [pscustomobject]@{
                    PSTypeName = 'IdLE.StepResult'
                    Name       = $ofName
                    Type       = $ofType
                    Status     = 'NotApplicable'
                    Attempts   = 1
                }

                $context.EventSink.WriteEvent(
                    'OnFailureStepNotApplicable',
                    "OnFailure step '$ofName' not applicable (condition not met).",
                    $ofName,
                    @{
                        StepType = $ofType
                        Index    = $j
                    }
                )

                $j++
                continue
            }

            # Runtime Precondition for OnFailure steps: evaluated immediately before execution.
            # OnFailure runs best-effort, so precondition failures skip the step but do not halt
            # remaining OnFailure steps. Non-IDictionary nodes are treated as failures (fail closed).
            $ofPrecondition = Get-IdlePropertyValue -Object $ofStep -Name 'Precondition'
            if ($null -ne $ofPrecondition) {
                $ofPreconditionPassed = $true
                if ($ofPrecondition -isnot [System.Collections.IDictionary]) {
                    $ofPreconditionPassed = $false
                }
                else {
                    # Validate that all non-Exists paths exist at execution time.
                    Assert-IdleConditionPathsResolvable -Condition ([hashtable]$ofPrecondition) -Context $preconditionContext -StepName $ofName -Source 'Precondition' -ExcludeExistsOperatorPaths
                    if (-not (Test-IdleCondition -Condition ([hashtable]$ofPrecondition) -Context $preconditionContext)) {
                        $ofPreconditionPassed = $false
                    }
                }

                if (-not $ofPreconditionPassed) {
                    $ofOnPreconditionFalse = [string](Get-IdlePropertyValue -Object $ofStep -Name 'OnPreconditionFalse')
                    if ([string]::IsNullOrWhiteSpace($ofOnPreconditionFalse)) { $ofOnPreconditionFalse = 'Blocked' }

                    # Always emit StepPreconditionFailed for engine observability.
                    $context.EventSink.WriteEvent(
                        'StepPreconditionFailed',
                        "OnFailure step '$ofName' precondition check failed.",
                        $ofName,
                        @{
                            StepType            = $ofType
                            Index               = $j
                            OnPreconditionFalse = $ofOnPreconditionFalse
                        }
                    )

                    # Emit the caller-configured PreconditionEvent if present.
                    $ofPcEvt = Get-IdlePropertyValue -Object $ofStep -Name 'PreconditionEvent'
                    if ($null -ne $ofPcEvt) {
                        $ofPcEvtType = [string](Get-IdlePropertyValue -Object $ofPcEvt -Name 'Type')
                        $ofPcEvtMsg = [string](Get-IdlePropertyValue -Object $ofPcEvt -Name 'Message')
                        $ofPcEvtData = Get-IdlePropertyValue -Object $ofPcEvt -Name 'Data'
                        $ofPcEvtDataHt = if ($ofPcEvtData -is [System.Collections.IDictionary]) { [hashtable]$ofPcEvtData } else { $null }
                        $context.EventSink.WriteEvent($ofPcEvtType, $ofPcEvtMsg, $ofName, $ofPcEvtDataHt)
                    }

                    if ($ofOnPreconditionFalse -eq 'Fail') {
                        $onFailureHadFailures = $true
                        $onFailureStepResults += [pscustomobject]@{
                            PSTypeName = 'IdLE.StepResult'
                            Name       = $ofName
                            Type       = $ofType
                            Status     = 'Failed'
                            Error      = 'Precondition check failed.'
                            Attempts   = 0
                        }
                        $context.EventSink.WriteEvent(
                            'StepFailed',
                            "OnFailure step '$ofName' failed (precondition check failed).",
                            $ofName,
                            @{
                                StepType = $ofType
                                Index    = $j
                                Error    = 'Precondition check failed.'
                            }
                        )
                    }
                    else {
                        # Blocked or Continue: skip this OnFailure step and proceed to the next.
                        $ofStatus = if ($ofOnPreconditionFalse -eq 'Continue') { 'PreconditionSkipped' } else { 'Blocked' }
                        $onFailureStepResults += [pscustomobject]@{
                            PSTypeName = 'IdLE.StepResult'
                            Name       = $ofName
                            Type       = $ofType
                            Status     = $ofStatus
                            Attempts   = 0
                        }
                        if ($ofOnPreconditionFalse -ne 'Continue') {
                            $context.EventSink.WriteEvent(
                                'StepBlocked',
                                "OnFailure step '$ofName' blocked (precondition check failed).",
                                $ofName,
                                @{
                                    StepType = $ofType
                                    Index    = $j
                                }
                            )
                        }
                    }

                    $j++
                    continue
                }
            }

            $context.EventSink.WriteEvent(
                'OnFailureStepStarted',
                "OnFailure step '$ofName' started.",
                $ofName,
                @{
                    StepType = $ofType
                    Index    = $j
                }
            )

            try {
                $impl = Resolve-IdleStepHandler -StepType ([string]$ofType) -StepRegistry $stepRegistry

                $supportedParams = Get-IdleCommandParameterNames -Handler $impl

                $invokeParams = @{}

                # Backwards compatibility: pass -Context only when the handler supports it.
                if ($supportedParams.Contains('Context')) {
                    $invokeParams.Context = $context
                }

                if ($null -ne $ofWith -and $supportedParams.Contains('With')) {
                    $invokeParams.With = $ofWith
                }

                if ($supportedParams.Contains('Step')) {
                    $invokeParams.Step = $ofStep
                }

                # Reuse safe-by-default transient retries for OnFailure steps.
                # - Retry parameters resolved from ExecutionOptions if provided.
                $retrySeed = "$corr|OnFailure|$ofType|$ofName|$j"
                $retryParams = Resolve-IdleStepRetryParameters -Step $ofStep -ExecutionOptions $ExecutionOptions
                $retry = Invoke-IdleWithRetry `
                    -Operation { & $impl @invokeParams } `
                    -MaxAttempts $retryParams.MaxAttempts `
                    -InitialDelayMilliseconds $retryParams.InitialDelayMilliseconds `
                    -BackoffFactor $retryParams.BackoffFactor `
                    -MaxDelayMilliseconds $retryParams.MaxDelayMilliseconds `
                    -JitterRatio $retryParams.JitterRatio `
                    -EventSink $context.EventSink `
                    -StepName $ofName `
                    -OperationName 'OnFailureStepExecution' `
                    -DeterministicSeed $retrySeed

                $result = $retry.Value
                $attempts = [int]$retry.Attempts

                if ($null -eq $result) {
                    $result = [pscustomobject]@{
                        PSTypeName = 'IdLE.StepResult'
                        Name       = $ofName
                        Type       = $ofType
                        Status     = 'Completed'
                        Attempts   = $attempts
                    }
                }
                else {
                    # Normalize result to include Attempts for observability (non-breaking).
                    if ($result.PSObject.Properties.Name -notcontains 'Attempts') {
                        $null = $result | Add-Member -MemberType NoteProperty -Name Attempts -Value $attempts -Force
                    }
                }

                $onFailureStepResults += $result

                if ($result.Status -eq 'Failed') {
                    $onFailureHadFailures = $true

                    $context.EventSink.WriteEvent(
                        'OnFailureStepFailed',
                        "OnFailure step '$ofName' failed.",
                        $ofName,
                        @{
                            StepType = $ofType
                            Index    = $j
                            Error    = $result.Error
                        }
                    )
                }
                else {
                    $context.EventSink.WriteEvent(
                        'OnFailureStepCompleted',
                        "OnFailure step '$ofName' completed.",
                        $ofName,
                        @{
                            StepType = $ofType
                            Index    = $j
                        }
                    )
                }
            }
            catch {
                $onFailureHadFailures = $true
                $err = $_

                $onFailureStepResults += [pscustomobject]@{
                    PSTypeName = 'IdLE.StepResult'
                    Name       = $ofName
                    Type       = $ofType
                    Status     = 'Failed'
                    Error      = $err.Exception.Message
                    Attempts   = 1
                }

                $context.EventSink.WriteEvent(
                    'OnFailureStepFailed',
                    "OnFailure step '$ofName' failed.",
                    $ofName,
                    @{
                        StepType = $ofType
                        Index    = $j
                        Error    = $err.Exception.Message
                    }
                )
            }

            $j++
        }

        $onFailureStatus = if ($onFailureHadFailures) { 'PartiallyFailed' } else { 'Completed' }

        $onFailure = [pscustomobject]@{
            PSTypeName = 'IdLE.OnFailureExecutionResult'
            Status     = $onFailureStatus
            Steps      = @($onFailureStepResults)
        }

        $context.EventSink.WriteEvent(
            'OnFailureCompleted',
            "OnFailureSteps finished (status: $onFailureStatus).",
            $null,
            @{
                Status    = $onFailureStatus
                StepCount = @($planOnFailureSteps).Count
            }
        )
    }

    # RunCompleted should always be the last event for deterministic event order.
    $context.EventSink.WriteEvent(
        'RunCompleted',
        "Plan execution finished (status: $runStatus).",
        $null,
        @{
            Status    = $runStatus
            StepCount = @($Plan.Steps).Count
        }
    )

    # Issue #48:
    # Redact provider configuration/state at the output boundary (execution result).
    $redactedProviders = if ($null -ne $effectiveProviders) {
        Copy-IdleRedactedObject -Value $effectiveProviders
    }
    else {
        $null
    }

    return [pscustomobject]@{
        PSTypeName    = 'IdLE.ExecutionResult'
        Status        = $runStatus
        CorrelationId = $corr
        Actor         = $actor
        Steps         = @($stepResults)
        OnFailure     = $onFailure
        Events        = $events
        Providers     = $redactedProviders
    }
}

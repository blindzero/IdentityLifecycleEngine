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
            $stepType = [string](Get-IdleStepField -Step $step -Name 'Type')
            if ($stepType -eq 'IdLE.Step.AcquireAuthSession') {
                $with = Get-IdleStepField -Step $step -Name 'With'
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
                if ($planProviders -is [System.Collections.IDictionary]) {
                    $effectiveProviders = $planProviders
                }
                elseif ($planProviders.PSObject -and $planProviders.PSObject.Properties) {
                    # Accept PSCustomObject with properties (e.g., StepRegistry, AuthSessionBroker)
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
    $stepResults = @()

    $i = 0
    foreach ($step in $Plan.Steps) {

        if ($null -eq $step) {
            continue
        }

        $stepName = [string](Get-IdleStepField -Step $step -Name 'Name')
        if ($null -eq $stepName) { $stepName = '' }

        $stepType = Get-IdleStepField -Step $step -Name 'Type'
        $stepWith = Get-IdleStepField -Step $step -Name 'With'
        $stepStatus = [string](Get-IdleStepField -Step $step -Name 'Status')
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

    $runStatus = if ($failed) { 'Failed' } else { 'Completed' }

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

    if ($failed -and @($planOnFailureSteps).Count -gt 0) {
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

function Invoke-IdlePlanObject {
    <#
    .SYNOPSIS
    Executes an IdLE plan object and returns a deterministic execution result.

    .DESCRIPTION
    Executes steps in order, emits structured events, and returns a stable execution result.

    Security:
    - ScriptBlocks are rejected in plan and providers.
    - The returned execution result is an output boundary: Providers are redacted.

    .PARAMETER Plan
    Plan object created by New-IdlePlanObject.

    .PARAMETER Providers
    Provider registry/collection passed through to execution.

    .PARAMETER EventSink
    Optional external event sink object. Must provide a WriteEvent(event) method.

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
        [object] $EventSink
    )

    function Get-IdleCommandParameterNames {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [ValidateNotNull()]
            [object] $Handler
        )

        # Returns a HashSet[string] of parameter names supported by the handler.
        $set = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

        if ($Handler -is [scriptblock]) {

            $paramBlock = $Handler.Ast.ParamBlock
            if ($null -eq $paramBlock) {
                return $set
            }

            foreach ($p in $paramBlock.Parameters) {
                # Parameter name is stored without the leading '$'
                $null = $set.Add([string]$p.Name.VariablePath.UserPath)
            }

            return $set
        }

        if ($Handler -is [System.Management.Automation.CommandInfo]) {
            foreach ($n in $Handler.Parameters.Keys) {
                $null = $set.Add([string]$n)
            }
            return $set
        }

        # Unknown handler shape: return an empty set.
        return $set
    }

    function Resolve-IdleStepHandler {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $StepType,

            [Parameter(Mandatory)]
            [ValidateNotNull()]
            [object] $StepRegistry
        )

        $handlerName = $null

        if ($StepRegistry -is [System.Collections.IDictionary]) {
            if ($StepRegistry.Contains($StepType)) {
                $handlerName = $StepRegistry[$StepType]
            }
        }
        else {
            if ($StepRegistry.PSObject.Properties.Name -contains $StepType) {
                $handlerName = $StepRegistry.$StepType
            }
        }

        if ($null -eq $handlerName -or [string]::IsNullOrWhiteSpace([string]$handlerName)) {
            throw [System.ArgumentException]::new("No step handler registered for step type '$StepType'.", 'Providers')
        }

        # Reject ScriptBlock handlers (secure default).
        if ($handlerName -is [scriptblock]) {
            throw [System.ArgumentException]::new(
                "Step registry handler for '$StepType' must be a function name (string), not a ScriptBlock.",
                'Providers'
            )
        }

        $cmd = Get-Command -Name ([string]$handlerName) -CommandType Function -ErrorAction Stop
        return $cmd
    }

    function Get-IdleStepField {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [AllowNull()]
            [object] $Step,

            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $Name
        )

        if ($null -eq $Step) { return $null }

        if ($Step -is [System.Collections.IDictionary]) {
            if ($Step.Contains($Name)) {
                return $Step[$Name]
            }
            return $null
        }

        $propNames = @($Step.PSObject.Properties.Name)
        if ($propNames -contains $Name) {
            return $Step.$Name
        }

        return $null
    }

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
    Assert-IdleNoScriptBlock -InputObject $Providers -Path 'Providers'

    # StepRegistry is constructed via helper to ensure built-in steps and host-provided steps can co-exist.
    $stepRegistry = Get-IdleStepRegistry -Providers $Providers

    $context = [pscustomobject]@{
        PSTypeName = 'IdLE.ExecutionContext'
        Plan       = $Plan
        Providers  = $Providers
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
        $optionsCopy = @{}
        foreach ($k in $normalizedOptions.Keys) {
            $optionsCopy[$k] = $normalizedOptions[$k]
        }

        if ($null -ne $this.CorrelationId) { $optionsCopy['CorrelationId'] = $this.CorrelationId }
        if ($null -ne $this.Actor) { $optionsCopy['Actor'] = $this.Actor }

        return $broker.AcquireAuthSession($Name, $optionsCopy)
    } -Force

    # Fail-fast security validation: Check if AuthSessionBroker is required but missing.
    # AcquireAuthSession steps require an AuthSessionBroker to be present in Providers.
    $requiresAuthBroker = $false
    foreach ($step in $Plan.Steps) {
        if ($null -eq $step) { continue }

        $stepType = $null
        if ($step -is [System.Collections.IDictionary]) {
            if ($step.Contains('Type')) {
                $stepType = $step['Type']
            }
        }
        else {
            $stepPropNames = @($step.PSObject.Properties.Name)
            $stepType = if ($stepPropNames -contains 'Type') { $step.Type } else { $null }
        }

        if ($stepType -eq 'IdLE.Step.AcquireAuthSession') {
            $requiresAuthBroker = $true
            break
        }
    }

    if ($requiresAuthBroker) {
        $broker = $null
        if ($Providers -is [System.Collections.IDictionary]) {
            if ($Providers.Contains('AuthSessionBroker')) {
                $broker = $Providers['AuthSessionBroker']
            }
        }
        else {
            if ($null -ne $Providers -and $Providers.PSObject.Properties.Name -contains 'AuthSessionBroker') {
                $broker = $Providers.AuthSessionBroker
            }
        }

        if ($null -eq $broker) {
            throw [System.InvalidOperationException]::new(
                'AuthSessionBroker is required but not configured. One or more steps require auth session acquisition. Provide Providers.AuthSessionBroker to proceed.'
            )
        }
    }

    $context.EventSink.WriteEvent('RunStarted', 'Plan execution started.', $null, @{
        CorrelationId = $corr
        Actor         = $actor
        StepCount     = @($Plan.Steps).Count
    })

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

            $context.EventSink.WriteEvent('StepNotApplicable', "Step '$stepName' not applicable (condition not met).", $stepName, @{
                StepType = $stepType
                Index    = $i
            })

            $i++
            continue
        }

        $context.EventSink.WriteEvent('StepStarted', "Step '$stepName' started.", $stepName, @{
            StepType = $stepType
            Index    = $i
        })

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
            $retrySeed = "$corr|$stepType|$stepName|$i"
            $retry = Invoke-IdleWithRetry -Operation { & $impl @invokeParams } -EventSink $context.EventSink -StepName $stepName -OperationName 'StepExecution' -DeterministicSeed $retrySeed

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

                $context.EventSink.WriteEvent('StepFailed', "Step '$stepName' failed.", $stepName, @{
                    StepType = $stepType
                    Index    = $i
                    Error    = $result.Error
                })

                break
            }

            $context.EventSink.WriteEvent('StepCompleted', "Step '$stepName' completed.", $stepName, @{
                StepType = $stepType
                Index    = $i
            })
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

            $context.EventSink.WriteEvent('StepFailed', "Step '$stepName' failed.", $stepName, @{
                StepType = $stepType
                Index    = $i
                Error    = $err.Exception.Message
            })

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
        $context.EventSink.WriteEvent('OnFailureStarted', 'Executing OnFailureSteps (best effort).', $null, @{
            OnFailureStepCount = @($planOnFailureSteps).Count
        })

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

                $context.EventSink.WriteEvent('OnFailureStepNotApplicable', "OnFailure step '$ofName' not applicable (condition not met).", $ofName, @{
                    StepType = $ofType
                    Index    = $j
                })

                $j++
                continue
            }

            $context.EventSink.WriteEvent('OnFailureStepStarted', "OnFailure step '$ofName' started.", $ofName, @{
                StepType = $ofType
                Index    = $j
            })

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
                $retrySeed = "$corr|OnFailure|$ofType|$ofName|$j"
                $retry = Invoke-IdleWithRetry -Operation { & $impl @invokeParams } -EventSink $context.EventSink -StepName $ofName -OperationName 'OnFailureStepExecution' -DeterministicSeed $retrySeed

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

                    $context.EventSink.WriteEvent('OnFailureStepFailed', "OnFailure step '$ofName' failed.", $ofName, @{
                        StepType = $ofType
                        Index    = $j
                        Error    = $result.Error
                    })
                }
                else {
                    $context.EventSink.WriteEvent('OnFailureStepCompleted', "OnFailure step '$ofName' completed.", $ofName, @{
                        StepType = $ofType
                        Index    = $j
                        Error    = $result.Error
                    })
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

                $context.EventSink.WriteEvent('OnFailureStepFailed', "OnFailure step '$ofName' failed.", $ofName, @{
                    StepType = $ofType
                    Index    = $j
                    Error    = $err.Exception.Message
                })
            }

            $j++
        }

        $onFailureStatus = if ($onFailureHadFailures) { 'PartiallyFailed' } else { 'Completed' }

        $onFailure = [pscustomobject]@{
            PSTypeName = 'IdLE.OnFailureExecutionResult'
            Status     = $onFailureStatus
            Steps      = @($onFailureStepResults)
        }

        $context.EventSink.WriteEvent('OnFailureCompleted', "OnFailureSteps finished (status: $onFailureStatus).", $null, @{
            Status    = $onFailureStatus
            StepCount = @($planOnFailureSteps).Count
        })
    }

    # RunCompleted should always be the last event for deterministic event order.
    $context.EventSink.WriteEvent('RunCompleted', "Plan execution finished (status: $runStatus).", $null, @{
        Status    = $runStatus
        StepCount = @($Plan.Steps).Count
    })

    # Issue #48:
    # Redact provider configuration/state at the output boundary (execution result).
    $redactedProviders = if ($null -ne $Providers) {
        Copy-IdleRedactedObject -Value $Providers
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

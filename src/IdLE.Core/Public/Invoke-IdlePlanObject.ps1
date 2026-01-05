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
    Provider registry/collection (may be $null).

    .PARAMETER EventSink
    Optional external event sink provided by the host. Must be an object with WriteEvent(event) method.

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
        [hashtable] $Providers,

        [Parameter()]
        [AllowNull()]
        [object] $EventSink
    )

    Assert-IdleNoScriptBlock -InputObject $Plan -Path 'Plan'
    Assert-IdleNoScriptBlock -InputObject $Providers -Path 'Providers'

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
                # Parameter name is stored as '$name' in the AST; we normalize to 'name'
                $name = $p.Name.VariablePath.UserPath
                if (-not [string]::IsNullOrWhiteSpace($name)) {
                    [void]$set.Add($name)
                }
            }

            return $set
        }

        # Command name or CommandInfo
        $command = $null

        if ($Handler -is [System.Management.Automation.CommandInfo]) {
            $command = $Handler
        }
        else {
            # Most commonly, registry returns a function name (string)
            $command = Get-Command -Name $Handler -ErrorAction Stop
        }

        foreach ($kv in $command.Parameters.GetEnumerator()) {
            [void]$set.Add($kv.Key)
        }

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

        # Get-IdleStepRegistry currently returns a hashtable that maps Step.Type -> handler function name (string).
        # We keep this resolver isolated so that internal representation changes don't leak into the engine loop.

        if ($StepRegistry -is [hashtable]) {
            if (-not $StepRegistry.ContainsKey($StepType)) {
                throw [System.ArgumentException]::new(
                    "No step handler registered for step type '$StepType'.",
                    'Providers'
                )
            }

            $handler = $StepRegistry[$StepType]
            if ($handler -isnot [string] -or [string]::IsNullOrWhiteSpace([string]$handler)) {
                throw [System.ArgumentException]::new(
                    "Step handler for step type '$StepType' must be a non-empty string (function name).",
                    'Providers'
                )
            }

            return ([string]$handler).Trim()
        }

        # Backward-compatible shape: registry object with GetStep(string) method.
        if ($StepRegistry.PSObject.Methods.Name -contains 'GetStep') {
            return $StepRegistry.GetStep($StepType)
        }

        throw [System.ArgumentException]::new(
            'Step registry must be a hashtable mapping Step.Type to a handler function name (string).',
            'Providers'
        )
    }

    $events = [System.Collections.Generic.List[object]]::new()

    # Resolve request/correlation/actor early because New-IdleEventSink requires CorrelationId.
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

    # Host may pass an external sink. If none is provided, we still buffer events internally.
    $engineEventSink = New-IdleEventSink -CorrelationId $corr -Actor $actor -ExternalEventSink $EventSink -EventBuffer $events

    # StepRegistry is constructed via helper to ensure built-in steps and host-provided steps can co-exist.
    $stepRegistry = Get-IdleStepRegistry -Providers $Providers

    $context = [pscustomobject]@{
        PSTypeName = 'IdLE.ExecutionContext'
        Plan       = $Plan
        Providers  = $Providers
        EventSink  = $engineEventSink
    }

    $context.EventSink.WriteEvent('RunStarted', "Plan execution started (correlationId: $corr).", $null, @{
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

        $stepPropNames = @($step.PSObject.Properties.Name)

        $stepName = if ($stepPropNames -contains 'Name') { $step.Name } else { $null }
        $stepType = if ($stepPropNames -contains 'Type') { $step.Type } else { $null }
        $stepWith = if ($stepPropNames -contains 'With') { $step.With } else { $null }
        $stepStatus = if ($stepPropNames -contains 'Status') { [string]$step.Status } else { '' }

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

            $invokeParams = @{
                Context = $context
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
            $retry = Invoke-IdleWithRetry -Operation { & $impl @invokeParams } -EventSink $context.EventSink -StepName ([string]$stepName) -OperationName 'StepExecution' -DeterministicSeed $retrySeed

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
        Steps         = $stepResults
        Events        = $events
        Providers     = $redactedProviders
    }
}

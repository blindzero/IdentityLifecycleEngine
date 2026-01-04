function Invoke-IdlePlanObject {
    <#
    .SYNOPSIS
    Executes a plan object and returns a deterministic execution result.

    .DESCRIPTION
    Executes steps in order and records step results and events. This is the core execution
    function used by Invoke-IdlePlan.

    The returned execution result is considered an output boundary. Sensitive information
    must be redacted from exported data surfaces.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Plan,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable] $Providers
    )

    Assert-IdleNoScriptBlock -InputObject $Plan -Path 'Plan'
    Assert-IdleNoScriptBlock -InputObject $Providers -Path 'Providers'

    $events = [System.Collections.Generic.List[object]]::new()

    $stepResults = @()

    $runStatus = 'Completed'

    $request = $Plan.Request
    $corr = $request.CorrelationId
    $actor = $request.Actor

    $stepRegistry = Get-IdleStepRegistry -Providers $Providers

    $context = [pscustomobject]@{
        PSTypeName = 'IdLE.ExecutionContext'
        Plan       = $Plan
        Providers  = $Providers

        # Object-based, stable eventing contract.
        EventSink  = [pscustomobject]@{
            PSTypeName = 'IdLE.EventSink'
            WriteEvent = {
                param(
                    [Parameter(Mandatory)]
                    [ValidateNotNullOrEmpty()]
                    [string] $Name,

                    [Parameter(Mandatory)]
                    [ValidateNotNullOrEmpty()]
                    [string] $Message,

                    [Parameter()]
                    [AllowNull()]
                    [string] $StepName,

                    [Parameter()]
                    [AllowNull()]
                    [object] $Data
                )

                $evt = [pscustomobject]@{
                    PSTypeName = 'IdLE.Event'
                    Name       = $Name
                    Message    = $Message
                    StepName   = $StepName
                    Data       = $Data
                }

                Write-IdleEvent -Event $evt -EventSink $null -EventBuffer $events
            }
        }

        # Backwards compatible alias for older hosts/tests.
        WriteEvent = {
            param(
                [Parameter(Mandatory)]
                [ValidateNotNullOrEmpty()]
                [string] $Name,

                [Parameter(Mandatory)]
                [ValidateNotNullOrEmpty()]
                [string] $Message,

                [Parameter()]
                [AllowNull()]
                [string] $StepName,

                [Parameter()]
                [AllowNull()]
                [object] $Data
            )

            $this.EventSink.WriteEvent($Name, $Message, $StepName, $Data)
        }
    }

    $context.EventSink.WriteEvent('RunStarted', "Plan execution started (correlationId: $corr).", $null, @{
        CorrelationId = $corr
        Actor         = $actor
        StepCount     = @($Plan.Steps).Count
    })

    $i = 0
    foreach ($step in $Plan.Steps) {
        $i++

        $stepName = $step.Name
        $stepType = $step.Type
        $stepWith = $step.With

        $context.EventSink.WriteEvent('StepStarted', "Step '$stepName' started.", $stepName, @{
            StepType = $stepType
            Index    = $i
        })

        try {
            $impl = $stepRegistry.GetStep($stepType)

            $invokeParams = @{
                Context = $context
            }

            if ($null -ne $stepWith) {
                $invokeParams.With = $stepWith
            }

            $result = & $impl @invokeParams

            if ($null -eq $result) {
                $result = [pscustomobject]@{
                    PSTypeName = 'IdLE.StepResult'
                    Name       = $stepName
                    Type       = $stepType
                    Status     = 'Completed'
                    Changed    = $false
                    Error      = $null
                    Attempts   = 1
                }
            }

            $stepResults += $result

            if ($result.Status -eq 'Failed') {
                $runStatus = 'Failed'

                $context.EventSink.WriteEvent('StepFailed', "Step '$stepName' failed.", $stepName, @{
                    StepType = $stepType
                    Index    = $i
                    Error    = $result.Error
                })

                # Fail-fast in this increment.
                break
            }

            $context.EventSink.WriteEvent('StepCompleted', "Step '$stepName' completed (changed: $($result.Changed)).", $stepName, @{
                StepType = $stepType
                Index    = $i
                Changed  = $result.Changed
            })
        }
        catch {
            $err = $_
            $runStatus = 'Failed'

            $stepResults += [pscustomobject]@{
                PSTypeName = 'IdLE.StepResult'
                Name       = $stepName
                Type       = $stepType
                Status     = 'Failed'
                Changed    = $false
                Error      = $err.Exception.Message
                Attempts   = 1
            }

            $context.EventSink.WriteEvent('StepFailed', "Step '$stepName' failed.", $stepName, @{
                StepType = $stepType
                Index    = $i
                Error    = $err.Exception.Message
            })

            # Fail-fast in this increment.
            break
        }
    }

    $context.EventSink.WriteEvent('RunCompleted', "Plan execution finished (status: $runStatus).", $null, @{
        Status    = $runStatus
        StepCount = @($Plan.Steps).Count
    })

    # Redact provider configuration/state at the output boundary (execution result).
    $redactedProviders = Copy-IdleRedactedObject -Value $Providers

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

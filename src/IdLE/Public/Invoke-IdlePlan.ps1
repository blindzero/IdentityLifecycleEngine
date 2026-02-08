function Invoke-IdlePlan {
    <#
    .SYNOPSIS
    Executes an IdLE plan.

    .DESCRIPTION
    Executes a plan deterministically and emits structured events.
    Delegates execution to IdLE.Core.

    Provider resolution:
    - If -Providers is supplied, it is used for execution.
    - If -Providers is not supplied, Plan.Providers is used if available.
    - If neither is present, execution fails early with a clear error message.

    .PARAMETER Plan
    The plan object created by New-IdlePlan.

    .PARAMETER Providers
    Provider registry/collection passed through to execution.
    If omitted and Plan.Providers exists, Plan.Providers will be used.
    If supplied, overrides Plan.Providers.

    .PARAMETER EventSink
    Optional external event sink for streaming. Must be an object with a WriteEvent(event) method.

    .PARAMETER ExecutionOptions
    Optional host-owned execution options. Supports retry profile configuration.
    Must be a hashtable with optional keys: RetryProfiles, DefaultRetryProfile.

    .EXAMPLE
    # Default: plan built with providers, execution uses Plan.Providers
    $providers = @{ Identity = $provider; AuthSessionBroker = $broker }
    $plan = New-IdlePlan -WorkflowPath ./joiner.psd1 -Request $req -Providers $providers
    Invoke-IdlePlan -Plan $plan

    .EXAMPLE
    # Override: explicit -Providers at invoke time
    Invoke-IdlePlan -Plan $plan -Providers $otherProviders

    .EXAMPLE
    $execOptions = @{
        RetryProfiles = @{
            Default = @{ MaxAttempts = 3; InitialDelayMilliseconds = 200 }
            ExchangeOnline = @{ MaxAttempts = 6; InitialDelayMilliseconds = 500 }
        }
        DefaultRetryProfile = 'Default'
    }
    Invoke-IdlePlan -Plan $plan -ExecutionOptions $execOptions

    .OUTPUTS
    PSCustomObject (PSTypeName: IdLE.ExecutionResult)
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateNotNull()]
        [object] $Plan,

        [Parameter()]
        [AllowNull()]
        [hashtable] $Providers,

        [Parameter()]
        [AllowNull()]
        [object] $EventSink,

        [Parameter()]
        [AllowNull()]
        [hashtable] $ExecutionOptions
    )

    process {
        if (-not $PSCmdlet.ShouldProcess('IdLE Plan', 'Invoke')) {
            # For -WhatIf: return a minimal preview object.
            # Keep the public output contract stable by always including OnFailure.
            $correlationId = $null
            if ($Plan.PSObject.Properties.Name -contains 'CorrelationId') {
                $correlationId = [string]$Plan.CorrelationId
            }

            $actor = $null
            if ($Plan.PSObject.Properties.Name -contains 'Actor') {
                $actor = [string]$Plan.Actor
            }
            elseif ($Plan.PSObject.Properties.Name -contains 'Request' -and $null -ne $Plan.Request) {
                if ($Plan.Request.PSObject.Properties.Name -contains 'Actor') {
                    $actor = [string]$Plan.Request.Actor
                }
            }

            return [pscustomobject]@{
                PSTypeName    = 'IdLE.ExecutionResult'
                Status        = 'WhatIf'
                CorrelationId = $correlationId
                Actor         = $actor
                Steps         = @($Plan.Steps)
                OnFailure     = [pscustomobject]@{
                    PSTypeName = 'IdLE.OnFailureExecutionResult'
                    Status     = 'NotRun'
                    Steps      = @()
                }
                Events        = @()
            }
        }

        return Invoke-IdlePlanObject -Plan $Plan -Providers $Providers -EventSink $EventSink -ExecutionOptions $ExecutionOptions
    }
}

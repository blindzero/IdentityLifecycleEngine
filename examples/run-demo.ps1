#requires -Version 7.0
Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot '..\src\IdLE\IdLE.psd1') -Force

$workflowPath = Join-Path $PSScriptRoot 'workflows\joiner-with-when.psd1'

$request = New-IdleLifecycleRequest -LifecycleEvent 'Joiner' -Actor 'example-user'

$plan = New-IdlePlan -WorkflowPath $workflowPath -Request $request

# Host-provided step registry:
# The handler can be a scriptblock (ideal for tests/examples) or a function name.
$emitHandler = {
    param($Context, $Step)

    # Support both hashtable/dictionary and PSCustomObject step shapes.
    $stepName = $null
    $stepType = $null
    $with     = $null

    if ($Step -is [System.Collections.IDictionary]) {
        $stepName = if ($Step.Contains('Name')) { [string]$Step['Name'] } else { $null }
        $stepType = if ($Step.Contains('Type')) { [string]$Step['Type'] } else { $null }
        $with     = if ($Step.Contains('With')) { $Step['With'] } else { $null }
    }
    else {
        $stepName = if ($Step.PSObject.Properties['Name']) { [string]$Step.Name } else { $null }
        $stepType = if ($Step.PSObject.Properties['Type']) { [string]$Step.Type } else { $null }
        $with     = if ($Step.PSObject.Properties['With']) { $Step.With } else { $null }
    }

    $msg = $null
    if ($with -is [System.Collections.IDictionary] -and $with.Contains('Message')) {
        $msg = [string]$with['Message']
    }
    elseif ($null -ne $with -and $with.PSObject.Properties['Message']) {
        $msg = [string]$with.Message
    }

    if ([string]::IsNullOrWhiteSpace($msg)) {
        $msg = 'EmitEvent executed.'
    }

    & $Context.WriteEvent 'Custom' $msg $stepName @{ StepType = $stepType }

    [pscustomobject]@{
        PSTypeName = 'IdLE.StepResult'
        Name       = $stepName
        Type       = $stepType
        Status     = 'Completed'
        Error      = $null
    }
}

$providers = @{
    StepRegistry = @{
        'IdLE.Step.EmitEvent' = $emitHandler
    }
}

$result = Invoke-IdlePlan -Plan $plan -Providers $providers

$result.Status
$result.Events | Format-Table TimestampUtc, Type, StepName, Message -AutoSize

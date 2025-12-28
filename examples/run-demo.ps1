#requires -Version 7.0
Set-StrictMode -Version Latest

function Test-IdleAnsiSupport {
    try {
        return ($Host.UI.SupportsVirtualTerminal -or $env:TERM -and $env:TERM -ne 'dumb')
    } catch { return $false }
}

$UseAnsi = Test-IdleAnsiSupport

function Write-DemoHeader {
    param([string]$Title)

    if ($UseAnsi) {
        Write-Host "$($PSStyle.Bold)$($PSStyle.Foreground.Cyan)$Title$($PSStyle.Reset)"
    } else {
        Write-Host $Title
    }
}

function Format-EventRow {
    param([object]$Event)

    $icons = @{
        RunStarted    = '🚀'
        RunCompleted  = '🏁'
        StepStarted   = '▶️'
        StepCompleted = '✅'
        StepSkipped   = '⏭️'
        StepFailed    = '❌'
        Custom        = '📝'
        Debug         = '🔎'
    }

    $icon = if ($icons.ContainsKey($Event.Type)) { $icons[$Event.Type] } else { '•' }

    $time = ([DateTime]$Event.TimestampUtc).ToLocalTime().ToString('HH:mm:ss.fff')
    $step = if ([string]::IsNullOrWhiteSpace($Event.StepName)) { '-' } else { [string]$Event.StepName }

    [pscustomobject]@{
        Time    = $time
        Type    = "$icon $($Event.Type)"
        Step    = $step
        Message = $Event.Message
    }
}

function Write-ResultSummary {
    param([object]$Result)

    $statusIcon = switch ($Result.Status) {
        'Completed' { '✅' }
        'Failed'    { '❌' }
        default     { 'ℹ️' }
    }

    if ($UseAnsi) {
        $color = if ($Result.Status -eq 'Completed') { $PSStyle.Foreground.Green } else { $PSStyle.Foreground.Red }
        Write-Host "$($PSStyle.Bold)$statusIcon Status: $color$($Result.Status)$($PSStyle.Reset)"
    } else {
        Write-Host "$statusIcon Status: $($Result.Status)"
    }

    $counts = $Result.Events | Group-Object Type | Sort-Object Name | ForEach-Object { "$($_.Name)=$($_.Count)" }
    Write-Host ("Events: " + ($counts -join ', '))
}

Import-Module (Join-Path $PSScriptRoot '..\src\IdLE\IdLE.psd1') -Force
Import-Module (Join-Path $PSScriptRoot '..\src\IdLE.Steps.Common\IdLE.Steps.Common.psd1') -Force

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

Write-DemoHeader "IdLE Demo – Plan Execution"
Write-ResultSummary -Result $result

Write-Host ""
Write-DemoHeader "Event Stream"
$result.Events |
    ForEach-Object { Format-EventRow $_ } |
    Format-Table Time, Type, Step, Message -AutoSize

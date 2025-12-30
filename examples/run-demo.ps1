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

    $msg = [string]$Event.Message

    # IMPORTANT: Show error details if the engine attached them.
    if ($Event.PSObject.Properties.Name -contains 'Data' -and $Event.Data -is [hashtable]) {
        if ($Event.Data.ContainsKey('Error') -and -not [string]::IsNullOrWhiteSpace([string]$Event.Data.Error)) {
            $msg = "$msg | ERROR: $([string]$Event.Data.Error)"
        }
    }

    [pscustomobject]@{
        Time    = $time
        Type    = "$icon $($Event.Type)"
        Step    = $step
        Message = $msg
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

# Import modules from the repo (path-based import, no global installation required).
Import-Module (Join-Path $PSScriptRoot '..\src\IdLE\IdLE.psd1') -Force -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot '..\src\IdLE.Steps.Common\IdLE.Steps.Common.psd1') -Force -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot '..\src\IdLE.Provider.Mock\IdLE.Provider.Mock.psd1') -Force -ErrorAction Stop

# Select demo workflow.
$workflowPath = Join-Path -Path $PSScriptRoot -ChildPath 'workflows\joiner-minimal-ensureattribute.psd1'

# Validate workflow early for clear errors.
Test-IdleWorkflow -WorkflowPath $workflowPath | Out-Null

# Create request and plan.
$request = New-IdleLifecycleRequest -LifecycleEvent 'Joiner' -Actor 'example-user'
$plan = New-IdlePlan -WorkflowPath $workflowPath -Request $request

# Host-provided providers.
$providers = @{
    Identity = New-IdleMockIdentityProvider
}

$result = Invoke-IdlePlan -Plan $plan -Providers $providers

Write-DemoHeader "IdLE Demo – Plan Execution"
Write-ResultSummary -Result $result

Write-Host ""
Write-DemoHeader "Step Results"
$result.Steps |
    Select-Object Name, Type, Status,
        @{ Name = 'Changed'; Expression = { if ($_.PSObject.Properties.Name -contains 'Changed') { $_.Changed } else { $null } } },
        Error |
    Format-Table -AutoSize

Write-Host ""
Write-DemoHeader "Event Stream"
$result.Events |
    ForEach-Object { Format-EventRow $_ } |
    Format-Table Time, Type, Step, Message -AutoSize

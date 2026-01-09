#requires -Version 7.0

[CmdletBinding(DefaultParameterSetName = 'Run')]
param(
    [Parameter(ParameterSetName = 'List')]
    [switch]$List,

    [Parameter(ParameterSetName = 'Run')]
    [string[]]$Example,

    [Parameter(ParameterSetName = 'Run')]
    [switch]$All,

    [Parameter(ParameterSetName = 'Run')]
    [ValidateRange(1, 50)]
    [int]$Repeat = 1,

    [Parameter(ParameterSetName = 'Run')]
    [switch]$FailFast,

    [Parameter(ParameterSetName = 'Run')]
    [switch]$NoColor
)

Set-StrictMode -Version Latest

function Test-IdleAnsiSupport {
    try {
        return ($Host.UI.SupportsVirtualTerminal -or ($env:TERM -and $env:TERM -ne 'dumb'))
    } catch { return $false }
}

function Test-IdleInteractiveHost {
    try {
        if (-not [Environment]::UserInteractive) { return $false }
        if ([Console]::IsInputRedirected) { return $false }
        if ($env:CI) { return $false }
        if (-not $Host.UI) { return $false }
        if (-not $Host.UI.RawUI) { return $false }
        return $true
    } catch {
        return $false
    }
}

$UseAnsi = if ($NoColor) { $false } else { Test-IdleAnsiSupport }

function Write-DemoHeader {
    param([Parameter(Mandatory)][string]$Title)

    if ($UseAnsi) {
        Write-Host "$($PSStyle.Bold)$($PSStyle.Foreground.Cyan)$Title$($PSStyle.Reset)"
    } else {
        Write-Host $Title
    }
}

function Format-EventRow {
    param([Parameter(Mandatory)][object]$Event)

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
    param([Parameter(Mandatory)][object]$Result)

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

function Get-IdleLifecycleEventFromWorkflowName {
    param([Parameter(Mandatory)][string]$Name)

    $n = $Name.ToLowerInvariant()

    if ($n.StartsWith('joiner')) { return 'Joiner' }
    if ($n.StartsWith('mover'))  { return 'Mover' }
    if ($n.StartsWith('leaver')) { return 'Leaver' }

    # Safe default for demos until workflows carry metadata for lifecycle event.
    return 'Joiner'
}

function Get-DemoWorkflows {
    $workflowDir = Join-Path -Path $PSScriptRoot -ChildPath 'workflows'

    if (-not (Test-Path -Path $workflowDir)) {
        throw "Workflow directory not found: $workflowDir"
    }

    Get-ChildItem -Path $workflowDir -Filter '*.psd1' -File |
        Sort-Object Name |
        ForEach-Object {
            [pscustomobject]@{
                Name = $_.BaseName
                Path = $_.FullName
                File = $_.Name
            }
        }
}

function Select-DemoWorkflows {
    param(
        [Parameter(Mandatory)]
        [object[]]$AvailableWorkflows,

        [string[]]$ExampleNames,

        [switch]$AllWorkflows
    )

    if ($AllWorkflows) { return $AvailableWorkflows }

    if ($ExampleNames -and $ExampleNames.Count -gt 0) {
        $lookup = @{}
        foreach ($wf in $AvailableWorkflows) {
            $lookup[$wf.Name.ToLowerInvariant()] = $wf
        }

        $selected = foreach ($name in $ExampleNames) {
            $key = $name.ToLowerInvariant()
            if (-not $lookup.ContainsKey($key)) {
                $available = ($AvailableWorkflows | Select-Object -ExpandProperty Name) -join ', '
                throw "Unknown example '$name'. Available: $available"
            }
            $lookup[$key]
        }

        return $selected
    }

    # Minimal interactive fallback (only if no parameters were provided).
    if (Test-IdleInteractiveHost) {
        Write-Host ""
        Write-DemoHeader "IdLE Demo – Select Example"
        $i = 1
        foreach ($wf in $AvailableWorkflows) {
            Write-Host ("[{0}] {1}" -f $i, $wf.Name)
            $i++
        }

        Write-Host ""
        $choiceRaw = Read-Host "Select an example (1-$($AvailableWorkflows.Count))"

        # IMPORTANT: [ref] requires an existing variable in StrictMode.
        $choice = 0
        if ([int]::TryParse($choiceRaw, [ref]$choice) -and $choice -ge 1 -and $choice -le $AvailableWorkflows.Count) {
            return @($AvailableWorkflows[$choice - 1])
        }

        Write-Host "Invalid selection. Using default: $($AvailableWorkflows[0].Name)"
        return @($AvailableWorkflows[0])
    }

    # Non-interactive default
    return @($AvailableWorkflows[0])
}

# Import modules from the repo (path-based import, no global installation required).
Import-Module (Join-Path $PSScriptRoot '..\src\IdLE\IdLE.psd1') -Force -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot '..\src\IdLE.Steps.Common\IdLE.Steps.Common.psd1') -Force -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot '..\src\IdLE.Provider.Mock\IdLE.Provider.Mock.psd1') -Force -ErrorAction Stop

$available = @(Get-DemoWorkflows)

if ($available.Count -eq 0) {
    throw "No workflows found in 'examples/workflows'."
}

if ($List) {
    Write-DemoHeader "IdLE Demo – Available Examples"
    $available | Select-Object Name, File | Format-Table -AutoSize
    return
}

$selected = @(Select-DemoWorkflows -AvailableWorkflows $available -ExampleNames $Example -AllWorkflows:$All)

$providers = @{
    Identity = New-IdleMockIdentityProvider
}

$allResults = @()

foreach ($wf in $selected) {
    for ($r = 1; $r -le $Repeat; $r++) {
        Write-Host ""
        Write-DemoHeader ("IdLE Demo – {0} (run {1}/{2})" -f $wf.Name, $r, $Repeat)

        Write-Host ""
        Write-DemoHeader "Validate"
        Test-IdleWorkflow -WorkflowPath $wf.Path | Out-Null
        Write-Host "✅ Workflow OK: $($wf.File)"

        Write-Host ""
        Write-DemoHeader "Plan"
        $lifecycleEvent = Get-IdleLifecycleEventFromWorkflowName -Name $wf.Name
        $request = New-IdleLifecycleRequest -LifecycleEvent $lifecycleEvent -Actor 'example-user'
        $plan = New-IdlePlan -WorkflowPath $wf.Path -Request $request -Providers $providers
        Write-Host ("Plan created: LifecycleEvent={0} | Steps={1}" -f $lifecycleEvent, ($plan.Steps | Measure-Object).Count)

        Write-Host ""
        Write-DemoHeader "Execute"
        $result = Invoke-IdlePlan -Plan $plan -Providers $providers
        $allResults += $result

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

        Write-Host ""
        Write-ResultSummary -Result $result

        if ($FailFast -and $result.Status -ne 'Completed') {
            throw "FailFast: execution failed for '$($wf.Name)'."
        }
    }
}

if ($selected.Count -gt 1 -or $Repeat -gt 1) {
    Write-Host ""
    Write-DemoHeader "Overall Summary"
    $allResults |
        Group-Object Status |
        Sort-Object Name |
        ForEach-Object { [pscustomobject]@{ Status = $_.Name; Count = $_.Count } } |
        Format-Table -AutoSize
}

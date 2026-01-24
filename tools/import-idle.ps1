[CmdletBinding()]
param()

# Developer helper to validate module import behavior in a repo clone.

$repoRoot = Split-Path -Path $PSScriptRoot -Parent
$idleManifest = Join-Path -Path $repoRoot -ChildPath 'src/IdLE/IdLE.psd1'
$workflowDir = Join-Path -Path $repoRoot -ChildPath 'examples/workflows'

Remove-Module -Name IdLE, IdLE.Core -Force -ErrorAction SilentlyContinue

Import-Module -Name $idleManifest -Force -ErrorAction Stop

# Show loaded modules (including nested modules)
Get-Module -All IdLE* |
    Select-Object Name, Version, Path |
    Sort-Object Name |
    Format-Table -AutoSize

# Verify public API surface
$expectedCommands = @(
    'Invoke-IdlePlan',
    'New-IdleLifecycleRequest',
    'New-IdlePlan',
    'Test-IdleWorkflow'
)

$missing = foreach ($name in $expectedCommands) {
    if (-not (Get-Command -Name $name -ErrorAction SilentlyContinue)) { $name }
}

if ($missing) {
    throw "IdLE import smoke test failed. Missing commands: $($missing -join ', ')"
}

Write-Host "IdLE public API is available." -ForegroundColor Green

# Validate all example workflows strictly (recursively search subdirectories)
$workflowPaths = Get-ChildItem -Path $workflowDir -Filter '*.psd1' -File -Recurse -ErrorAction Stop | Select-Object -ExpandProperty FullName
if (-not $workflowPaths) {
    throw "No workflow definition files found in: $workflowDir"
}

foreach ($wf in $workflowPaths) {
    Test-IdleWorkflow -WorkflowPath $wf
}

Write-Host "All example workflows validated successfully." -ForegroundColor Green

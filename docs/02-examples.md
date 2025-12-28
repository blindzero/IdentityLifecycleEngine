# Examples

Runnable examples live in the repository under `examples/`.

- `examples/run-demo.ps1` – end-to-end demo (Plan → Execute) with a host-provided Step Registry
- `examples/workflows/` – workflow definition samples (`.psd1`)

## Run the demo

From the repository root:

```powershell
pwsh -File .\examples\run-demo.ps1
```

The demo prints the execution status and a small event table.

## Plan → Execute (minimal)

IdLE separates **planning** from **execution**:

1) Create a request  
2) Build a deterministic plan from a workflow definition (`.psd1`)  
3) Execute the plan using a host-provided step registry (handlers)

Minimal example (mirrors `examples/run-demo.ps1`):

```powershell
$workflowPath = Join-Path $PSScriptRoot 'workflows\joiner-with-when.psd1'

$request = New-IdleLifecycleRequest -LifecycleEvent 'Joiner' -Actor 'example-user' # Actor optional
$plan    = New-IdlePlan -WorkflowPath $workflowPath -Request $request

# Providers are host-provided and can be mocked in tests.
$providers = @{}

$result = Invoke-IdlePlan -Plan $plan -Providers $providers
```

## Workflow definition (PSD1) – structure

Workflows are **data-only** and typically stored as `.psd1`.

Minimal shape:

```powershell
@{
  Name           = 'Joiner - Standard'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name    = 'Emit:Start'
      Step    = 'EmitEvent'
      Inputs  = @{ Message = 'Starting Joiner' }
    }
  )
}
```

## Declarative `When` conditions

Steps can be conditionally skipped using a declarative `When` block:

```powershell
When = @{
  Path   = 'Plan.LifecycleEvent'
  Equals = 'Joiner'
}
```

If the condition is not met:

- the step result status becomes `Skipped`
- a `StepSkipped` event is emitted

## Optional built-in steps

IdLE is engine-first. Step implementations are shipped in optional step modules.

Example:

```powershell
Import-Module ./src/IdLE.Steps.Common/IdLE.Steps.Common.psd1 -Force
```

(See `examples/run-demo.ps1` for a complete runnable flow.)

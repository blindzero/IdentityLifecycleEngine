# Examples

This folder contains runnable examples for IdLE.

## Run the demo

From the repository root:

```powershell
pwsh -File .\examples\Invoke-IdleDemo.ps1
```

The demo:

- builds a plan from a workflow (`.psd1`)
- executes the plan using mock providers
- prints step results and buffered events

## Workflow samples

Workflow samples are located in:

- `examples/workflows/`

Workflows are **data-only** PSD1 files. A minimal workflow looks like:

```powershell
@{
  Name           = 'Joiner - Minimal Demo'
  LifecycleEvent = 'Joiner'
  Steps          = @(
    @{
      Name = 'EmitHello'
      Type = 'IdLE.Step.EmitEvent'
      With = @{ Message = 'Hello from workflow.' }
    }
  )
}
```

For details, see `docs/usage/workflows.md`.

## Events

IdLE buffers all emitted events in the execution result:

```powershell
$result.Events | Select-Object Type, StepName, Message
```

Hosts can optionally stream events live by providing `-EventSink` as an object implementing `WriteEvent(event)`.

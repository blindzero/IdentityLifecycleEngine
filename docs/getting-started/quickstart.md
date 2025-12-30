# QuickStart

This quickstart walks through the IdLE flow:

1. Create a request
2. Build a plan from a workflow
3. Execute the plan with host-provided providers

## Run the repository demo

From the repository root:

```powershell
pwsh -File .\examples\run-demo.ps1
```

## Minimal plan and execute

```powershell
$workflowPath = Join-Path (Get-Location) 'examples\workflows\joiner-with-when.psd1'

$request = New-IdleLifecycleRequest -LifecycleEvent 'Joiner' -Actor 'example-user'
$plan    = New-IdlePlan -WorkflowPath $workflowPath -Request $request

$providers = @{}
$result = Invoke-IdlePlan -Plan $plan -Providers $providers
```

## Inspect results and events

Execution returns a result object containing step results and buffered events:

```powershell
$result.Status
$result.Steps
$result.Events | Select-Object Type, StepName, Message
```

## Optional: stream events with -EventSink

If a host wants live progress, it can provide an **object** event sink.
The sink must implement `WriteEvent(event)`.

> Security note: ScriptBlock sinks are not supported.

Example:

```powershell
$streamed = [System.Collections.Generic.List[object]]::new()

$sink = [pscustomobject]@{}
$null = Add-Member -InputObject $sink -MemberType ScriptMethod -Name 'WriteEvent' -Value {
  param($e)
  [void]$streamed.Add($e)
  Write-Host ("[{0}] {1}" -f $e.Type, $e.Message)
}

$result = Invoke-IdlePlan -Plan $plan -Providers $providers -EventSink $sink
```

## Next steps

- [Workflows](../usage/workflows.md)
- [Steps](../usage/steps.md)
- [Providers](../usage/providers.md)
- [Architecture](../advanced/architecture.md)

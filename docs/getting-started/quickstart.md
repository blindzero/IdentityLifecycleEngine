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
$workflowPath = Join-Path $PSScriptRoot 'workflows\joiner-with-when.psd1'

$request = New-IdleLifecycleRequest -LifecycleEvent 'Joiner' -Actor 'example-user'
$plan    = New-IdlePlan -WorkflowPath $workflowPath -Request $request

$providers = @{}
$result = Invoke-IdlePlan -Plan $plan -Providers $providers
```

## Next steps

- [Workflows](../usage/workflows.md)
- [Steps](../usage/steps.md)
- [Providers](../usage/providers.md)
- [Architecture](../advanced/architecture.md)

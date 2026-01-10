# QuickStart

This quickstart walks through the IdLE flow:

1. Create a request
2. Build a plan from a workflow
3. Execute the plan with host-provided providers

## If you installed IdLE from PowerShell Gallery

IdLE is an orchestration engine. To **execute** a plan you must provide provider implementations (for example: identity store,
entitlement store, messaging, etc.). If you only want a runnable end-to-end demo, follow the repository demo section below.

Next steps for library usage:

- Install IdLE: see [Installation](./installation.md)
- Learn the concepts: [Concept](../overview/concept.md)
- Cmdlets reference: [Cmdlets](../reference/cmdlets.md)
- Providers and contracts: [Providers](../usage/providers.md)

## Run the repository demo (recommended first run)

The repository includes a demo runner that showcases the full IdLE flow using predefined example workflows.

1. Clone the repository (or download the source archive from a GitHub release).
2. Run the demo script:

```powershell
.\examples\Invoke-IdleDemo.ps1
```

You can also list and run specific examples:

```powershell
.\examples\Invoke-IdleDemo.ps1 -List
.\examples\Invoke-IdleDemo.ps1 -Example <example-name-without-suffix>
```

...or simply run all

```powershell
.\examples\Invoke-IdleDemo.ps1 -All
```

## The manual example runs

For understanding how IdLE is used programmatically, you can execute a workflow manually without the demo runner.

```powershell
$workflowPath = Join-Path (Get-Location) 'examples\workflows\<example-file>'
$request = New-IdleLifecycleRequest -LifecycleEvent 'Joiner'
$plan    = New-IdlePlan -WorkflowPath $workflowPath -Request $request

$providers = @{
    Identity = New-IdleMockIdentityProvider
}
$result = Invoke-IdlePlan -Plan $plan -Providers $providers
```

When executing plans programmatically, IdLE returns a result object containing step results and buffered events.

```powershell
$result.Status
$result.Steps
$result.Events | Select-Object Type, StepName, Message
```

## Next steps

- [Workflows](../usage/workflows.md)
- [Steps](../usage/steps.md)
- [Providers](../usage/providers.md)
- [Architecture](../advanced/architecture.md)

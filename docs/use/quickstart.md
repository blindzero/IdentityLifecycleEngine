---
title: Quick Start
sidebar_label: Quick Start
---

# Quick Start

The repository contains a demo runner that showcases the full **Plan → Execute** flow using predefined example workflows.<br/>
Each example workflow is a single workflow definition `psd1`-file in `/examples/workflows/...` directories.

## Get Repository Demo

Clone the repository (or download the source archive from a GitHub release).

```powershell
git clone https://github.com/blindzero/IdentityLifecycleEngine
cd IdentityLifecycleEngine
```

## Run Demo

Our **Repository demo** provides sample workflows which are not provided by the module install from PowerShell Gallery package.

### 1. Show Demo Workflows

By default the **IdLE Demo** script uses only examples workflow definition from the `examples/workflows/mock` folder category to avoid dependency to real-life systems.

List available mock category examples:

```powershell
.\examples\Invoke-IdleDemo.ps1 -List
```

### 2. Run Demo Workflow

```powershell
.\examples\Invoke-IdleDemo.ps1
```

Select one of the workflow examples available, that does _not_ use real provider interactions and only use the mock provider interface.

Alternatively, select an example workflow with `-Example` parameter:

```powershell
.\examples\Invoke-IdleDemo.ps1 -Example <example-name-without-suffix>
```

Or run all mock workflows:

```powershell
.\examples\Invoke-IdleDemo.ps1 -All
```

What you should see:

- a lifecycle request is created
- a plan is built from a workflow definition (`.psd1`)
- the plan is executed with demo/mock providers
- the result contains step results and buffered events

### 3. Check other examples

We also provide additional "template" examples, which could be used with live systems. 

```powershell
.\examples\Invoke-IdleDemo.ps1 -List -Category All
```

:::warning

Use template examples with care as they connect and may cause harm to your live environments.

:::

---

## Run your first workflow

IdLE does not ship a “live system host”. A host (your script, CI job, or service) must provide provider instances
for execution. For a safe first run, IdLE ships mock providers that are sufficient to execute example workflows.

This is the smallest runnable program that demonstrates the full flow:

1. Create a request
2. Build a plan from a workflow
3. Execute with providers (mock)
4. Inspect result + events

### 1. Import Mock Provider

```powershell
Import-Module .\src\IdLE.Provider.Mock\IdLE.Provider.Mock.psd1 -Force
```

### 2. Select Workflow

Workflows are data files (`.psd1`). The quickest path is to reuse one of the repository examples,

- reference a workflow file from `examples/workflows`
- or copy and adapt a single example workflow file into your working directory

:::note

The mock provider below can be used with workflows that use following Step Types:

- IdLE.Step.EmitEvent
- IdLE.Step.ReadIdentity
- IdLE.Step.EnsureAttributes
- IdLE.Step.DisableIdentity
- IdLE.Step.EnableIdentity
- IdLE.Step.EnsureEntitlement

:::

```powershell
$workflow = Join-Path 'C:\path\to\IdentityLifecycleEngine' 'examples\workflows\<example-file>.psd1'
```

### 3. Create Request Object

With the following command we create a simple 'Joiner' request.

```powershell
$request = New-IdleRequest -LifecycleEvent 'Joiner'
```

### 4. Select providers

For first run, we just use our internal mock provider.

```powershell
$providers = @{
    Identity = New-IdleMockIdentityProvider
}
```

### 5. Build the plan with providers

The plan evaluates validity of the request in combination with the workflow definition.

```powershell
$plan = New-IdlePlan -WorkflowPath $workflow -Request $request -Providers $providers
```

### 6. Execute the plan

```powershell
# Execute without re-supplying providers (uses Plan.Providers automatically)
$result = Invoke-IdlePlan -Plan $plan
```

### 7. Inspect result + events

```powershell
$result.Status
$result.Steps
$result.Events | Select-Object Type, StepName, Message
```

:::tip

- If your workflow contains steps that require additional provider roles (e.g. `Messaging`, `Entitlement`),
  you must add them to `$providers`.
- Many steps default to the provider alias `'Identity'` unless a step explicitly sets `With.Provider`.
- You can override providers at execution time by passing `-Providers` to `Invoke-IdlePlan`.

:::


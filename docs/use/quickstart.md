---
title: Quick Start
sidebar_label: Quick Start
---

# Quick Start

This page gets you from **zero → first successful run** as fast as possible.

IdLE is an orchestration engine. That means:

- **Planning** builds a deterministic plan (safe, no external changes)
- **Execution** runs that plan using **provider implementations** (system adapters) supplied by the host

If you just want a runnable end-to-end first run, start with **Repository demo**.
If you want to use IdLE as a library from the PowerShell Gallery package, follow **Install from PowerShell Gallery**.

---

## 1) Repository demo (recommended first run)

The repository contains a demo runner that showcases the full **Plan → Execute** flow using predefined example workflows.

1. Clone the repository (or download the source archive from a GitHub release).
2. Run the demo script:

```powershell
pwsh -File .\examples\Invoke-IdleDemo.ps1
```

List available examples:

```powershell
pwsh -File .\examples\Invoke-IdleDemo.ps1 -List
```

Run a specific example:

```powershell
pwsh -File .\examples\Invoke-IdleDemo.ps1 -Example <example-name-without-suffix>
```

Run all examples:

```powershell
pwsh -File .\examples\Invoke-IdleDemo.ps1 -All
```

What you should see:

- a lifecycle request is created
- a plan is built from a workflow definition (`.psd1`)
- the plan is executed with demo/mock providers
- the result contains step results and buffered events

---

## 2) Install from PowerShell Gallery

Install and import the meta module:

```powershell
Install-Module -Name IdLE -Scope CurrentUser
Import-Module IdLE
```

> IdLE does not ship a “live system host”. A host (your script, CI job, or service) must provide provider instances
> for execution. For a safe first run, IdLE ships mock providers that are sufficient to execute example workflows.

---

## 3) First run from an installed package (mock providers + example workflow)

This is the smallest runnable program that demonstrates the full flow:

1. Create a request
2. Build a plan from a workflow
3. Execute with providers (mock)
4. Inspect result + events

### Use an example workflow from the repository

Workflows are data files (`.psd1`). The quickest path is to reuse one of the repository examples:

- clone the repository, then reference a workflow file from `examples/workflows`
- or copy a single example workflow file into your working directory

Example (workflow from repo checkout):

```powershell
# 0) Point to an example workflow file
$workflowPath = Join-Path 'C:\path\to\IdentityLifecycleEngine' 'examples\workflows\<example-file>.psd1'

# 1) Create the request (your input intent)
$request = New-IdleLifecycleRequest -LifecycleEvent 'Joiner'

# 2) Build the plan (deterministic, data-only)
$plan = New-IdlePlan -WorkflowPath $workflowPath -Request $request

# 3) Provide providers (mock providers are included for first runs)
$providers = @{
    Identity = New-IdleMockIdentityProvider
}

# 4) Execute the plan
$result = Invoke-IdlePlan -Plan $plan -Providers $providers

# 5) Inspect result + events
$result.Status
$result.Steps
$result.Events | Select-Object Type, StepName, Message
```

Notes:

- If your workflow contains steps that require additional provider roles (e.g. `Messaging`, `Entitlement`),
  you must add them to `$providers`.
- Many steps default to the provider alias `'Identity'` unless a step explicitly sets `With.Provider`.

---

## 4) Using real providers (host integration)

To execute against real systems, you supply provider implementations that:

- implement the required provider contract methods for the steps you use
- advertise capabilities via `GetCapabilities()` (used for planning-time validation)

Example structure:

```powershell
$providers = @{
    Identity = $myIdentityProvider
    # Entitlement = $myEntitlementProvider
    # Messaging  = $myMessagingProvider

    # Optional (recommended): host-provided auth session broker
    # AuthSessionBroker = $myAuthSessionBroker
}
```

During planning, IdLE validates prerequisites and fails early if required capabilities are missing.

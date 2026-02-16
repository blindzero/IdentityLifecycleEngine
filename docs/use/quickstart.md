---
title: Quick Start
sidebar_label: Quick Start
---

# Quick Start

This Quick Start gets you from **zero** to a first successful run of the IdLE lifecycle:

1. Define a **workflow** (data-only `.psd1`)
2. Create a **request** (business intent)
3. Build a **plan** (validation + template resolution)
4. **Invoke** the plan (execution + events)

:::info
IdLE does not ship a “live system host”.
Your **host** (script, CI job, service) supplies provider instances and (if needed) authentication.
:::

---

## Prerequisites

- PowerShell **7.x** or later (`pwsh`)
- The IdLE modules installed (for further details see [Installation](installation.md))

---

## 1) Install and import modules

```powershell
# IdLE meta module (Core + Steps)
Install-Module -Name IdLE -Scope CurrentUser
Import-Module -Name IdLE

# Mock provider (safe, no real systems touched)
Install-Module -Name IdLE.Provider.Mock -Scope CurrentUser
Import-Module -Name IdLE.Provider.Mock
```

:::tip
If you are running in CI, consider `-Scope AllUsers` or a dedicated PowerShellGet cache, depending on your environment.
:::

---

## 2) Create a minimal workflow file

Workflows are **data-only** PowerShell hashtables stored as `.psd1` files.

Create a temporary workflow file with two steps:

- `IdLE.Step.EmitEvent` (no external side effects)
- `IdLE.Step.EnsureAttributes` (runs against the mock provider)

```powershell
$workflowPath = Join-Path $env:TEMP 'idle-quickstart-joiner.psd1'

$workflowContent = @'
@{
  Name           = 'QuickStart - Joiner (Mock)'
  LifecycleEvent = 'Joiner'

  Steps          = @(
    @{
      Name = 'Emit start'
      Type = 'IdLE.Step.EmitEvent'
      With = @{
        Message = 'Starting Joiner workflow (QuickStart)'
      }
    }

    @{
      Name = 'Ensure demo attributes'
      Type = 'IdLE.Step.EnsureAttributes'
      With = @{
        Provider    = 'Identity'
        IdentityKey = '{{Request.IdentityKeys.EmployeeId}}'
        Attributes  = @{
          GivenName = '{{Request.DesiredState.GivenName}}'
          Surname   = '{{Request.DesiredState.Surname}}'
        }
      }
    }
  )
}
'@

Set-Content -Path $workflowPath -Value $workflowContent -Encoding UTF8 -Force

$workflowPath
```

:::warning
Workflow definitions are **data-only**. Do not embed executable code (ScriptBlocks).
This is a core security boundary in IdLE.
:::

---

## 3) Create a request

A request represents business intent (Joiner/Mover/Leaver) plus input data.

```powershell
$request = New-IdleRequest -LifecycleEvent 'Joiner' -IdentityKeys @{
  EmployeeId = '12345'
} -DesiredState @{
  GivenName = 'Max'
  Surname   = 'Power'
}
```

---

## 4) Provide providers (host responsibility)

Providers are supplied by your host. For this Quick Start we use the in-memory mock provider.

```powershell
$providers = @{
  Identity = New-IdleMockIdentityProvider
}
```

---

## 5) Build the plan (validation + template resolution)

Plan building is a **fail-fast** step. IdLE validates the workflow and resolves templates like
`{{Request.DesiredState.GivenName}}`.

```powershell
$plan = New-IdlePlan -WorkflowPath $workflowPath -Request $request -Providers $providers
```

---

## 6) Invoke the plan

```powershell
$result = Invoke-IdlePlan -Plan $plan
```

---

## 7) Inspect the result and events

```powershell
$result.Status

# Step results (name, status, timings, messages)
$result.Steps | Select-Object Name, Status, Type

# Buffered events
$result.Events | Select-Object StepName, Message, Type, TimestampUtc
```

---

## What to do next

- Learn workflow structure, templates, and conditions: [Workflows & Steps](workflows.md)
- Understand provider mapping and authentication patterns: [Providers](providers.md)
- Export a plan for review / CI artifacts: [Plan Export](plan-export.md)

If you want to look up details in the reference:

- [Cmdlets](../reference/cmdlets.md)
- [Steps](../reference/steps.md)
- [Providers](../reference/providers.md)

---

## Explore repository examples (optional)

The IdLE repository contains an example runner and additional workflow samples.
This is useful to browse patterns and larger examples, but it is **not required** for normal IdLE usage.

```powershell
git clone https://github.com/blindzero/IdentityLifecycleEngine
cd IdentityLifecycleEngine

# List demo workflows (mock category by default)
.\examples\Invoke-IdleDemo.ps1 -List

# Run one demo workflow (interactive selection)
.\examples\Invoke-IdleDemo.ps1
```

:::warning
Some example categories may connect to real systems and can cause changes.
Only run examples you fully understand and only in safe environments.
:::

```powershell
# List all demos - also run templates
.\examples\Invoke-IdleDemo.ps1 -List -Category All
```

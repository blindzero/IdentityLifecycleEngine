---
title: Workflows & Steps
sidebar_label: Workflows / Steps
---

Workflows are **data-only** PowerShell hashtables (`.psd1`) that describe **which steps** should be planned and executed for a specific lifecycle event. Workflows define **what** IdLE should do for a lifecycle event (Joiner/Mover/Leaver).

A workflow is a **data-only** PowerShell hashtable stored in a `.psd1` file. It describes the ordered steps to execute, plus optional conditions and error handling.

Workflows are designed for **admins and workflow authors**:

- You define *what should happen* (steps and their configuration).
- IdLE builds a **plan** and then **executes** it.
- Providers implement the system-specific operations.

## How workflows are used in the lifecycle

1. You write the workflow definition (`.psd1`).
2. You create a request (intent + inputs).
3. You build a plan (IdLE validates and resolves templates).
4. You invoke the plan.

:::info
For specification-level details on step types, use the [Step Reference](../reference/steps.md) section. \
Otherwise, start with [Quick Start](quickstart.md).
:::

---

## Plan vs Execute

When you run IdLE, it happens in two distinct phases:

1. **Planning (Plan Build)**  
   IdLE reads the workflow definition and builds a plan of steps.

   - `Condition` is evaluated here.
   - If a condition is false, the step is marked as `NotApplicable`.

2. **Execution (Plan Run)**  
   IdLE executes the planned steps and records results.

   - `Preconditions` are evaluated here.
   - If a precondition is false, `OnPreconditionFalse` decides what happens (for example `Skip` or `Fail`).

---

## What a workflow contains

At a high level, a workflow contains:

- metadata (name, lifecycle event)
- a list of steps (ordered)
- per-step configuration (`With`)
- per-step optional execution logic (`Condition`, `Preconditions`, `OnFailureSteps`, etc.)

The Big Picture is described in [Concepts](../about/concepts.md).

A step is a self-contained unit of work. Most steps follow this pattern:

- `Name` (string) – a human-readable identifier
- `Type` (string) – the step type (for example `IdLE.Step.EnsureAttribute`)
- `With` (hashtable) – step-specific configuration
- `Condition` (hashtable, optional) – optional planning-time applicability
- `Preconditions` (hashtable, optional) – optional execution-time guard
- `OnPreconditionFalse` (string, optional) – behavior when the precondition is false

> Step types define which keys are supported inside `With`. See the step reference for details.

### Step execution controls

Each step supports several optional execution control properties:

| Property | Evaluated at | Purpose |
|---|---|---|
| `Condition` | Plan time | Include or skip the step based on request/intent data during planning. See [Conditions](workflows/conditions.md) |
| `Preconditions` | Execution time (runtime) | Guard the step against stale or unsafe state immediately before execution. See Runtime [Preconditions](workflows/preconditions.md). |
| `OnFailureSteps` | After failure (workflow-level) | Cleanup/rollback steps run after a primary step fails. |

:::warning Do not confuse Conditions and Preconditions
**Conditions** decide step applicability during **planning** (a step becomes `NotApplicable`).  
**Preconditions** guard step behavior during **execution** (`Skip` / `Fail` / `Continue`).

---

## Template Substitution

Many step configurations use **template substitution** to insert values from `Plan`, `Request`, and `Workflow` into strings (for example to build a UPN or display name). \
These `{{path}}` placeholders that are resolved against the
request during plan build (`New-IdlePlan`). Multiple placeholders may appear in a single value.

```powershell
IdentityKey = '{{Request.IdentityKeys.sAMAccountName}}'
DisplayName = '{{Request.Intent.GivenName}} {{Request.Intent.SurnameName}}'
Message     = 'User {{Request.Intent.DisplayName}} is joining.'
```

See: [Template Substitution](./workflows/templates)

---

## Minimal workflow example

This example shows a small workflow with:

- a value containing a [template substition](./workflows/templates.md)
- a step that is only applicable for `Joiner` ([Condition](./workflows/conditions.md))
- a step that is guarded at runtime ([Preconditions](./workflows/preconditions.md))


```powershell
@{
  Name           = 'Joiner - Standard'
  LifecycleEvent = 'Joiner'

  Steps          = @(
    @{
      Name = 'Emit start'
      Type = 'IdLE.Step.EmitEvent'
      With = @{ Message = 'Starting Joiner for {{Request.Intent.FullName}}' }
    }

    @{
      Name = 'Provision only for Joiner'
      Type = 'IdLE.Step.EmitEvent'

      Condition = @{
        Equals = @{ Path = 'Plan.LifecycleEvent'; Value = 'Joiner' }
      }

      With = @{ Message = 'Provisioning for Joiner' }
    }

    @{
      Name = 'Disable identity only if it exists'
      Type = 'IdLE.Step.DisableIdentity'

      Preconditions = @{
        Equals = @{ Path = 'Request.Context.IdentityExists'; Value = 'True' }
      }

      OnPreconditionFalse = 'Skip'
    }
  )
}
```

---

## Common pitfalls

- **Not data-only:** embedding ScriptBlocks or secrets in workflow files (not allowed).
- **Wrong StepType name:** the step module is not imported or the type name is wrong.
- **Missing provider alias:** `With.Provider = 'Identity'` but the host did not supply that alias.
- **Template paths resolve to null:** the referenced request/identity data is missing.

---

## Reference

For full definitions and reference, see:

- [Reference](../reference/intro-reference.md)
- [Reference: Step Types](../reference/steps.md)
- [Reference: Providers](../reference/providers.md)

---
title: Workflows & Steps
sidebar_label: Workflows / Steps
---

Workflows define **what** IdLE should do for a lifecycle event (Joiner/Mover/Leaver).

A workflow is a **data-only** PowerShell hashtable stored in a `.psd1` file. It describes the ordered steps to execute, plus optional conditions and error handling.

:::info
For specification-level details (schema, templates, conditions, and validation rules), use the [Reference](../reference/intro-reference.md) section.
:::

---

## What a workflow contains

At a high level, a workflow contains:

- metadata (name, lifecycle event)
- a list of steps (ordered)
- per-step configuration (`With`)
- optional execution logic (conditions, `OnFailureSteps`, etc.)

The Big Picture is described in [Concepts](../about/concepts.md).

---

## Minimal workflow example

```powershell
@{
  Name           = 'Joiner - Minimal'
  LifecycleEvent = 'Joiner'

  Steps          = @(
    @{
      Name = 'Emit start'
      Type = 'IdLE.Step.EmitEvent'
      With = @{
        Message = 'Starting Joiner workflow'
      }
    }
  )
}
```

---

## How workflows are used in the lifecycle

1. You write the workflow definition (`.psd1`).
2. You create a request (intent + inputs).
3. You build a plan (IdLE validates and resolves templates).
4. You invoke the plan.

Start with [Quick Start](quickstart.md).

---

## Common pitfalls

- **Not data-only:** embedding ScriptBlocks or secrets in workflow files (not allowed).
- **Wrong StepType name:** the step module is not imported or the type name is wrong.
- **Missing provider alias:** `With.Provider = 'Identity'` but the host did not supply that alias.
- **Template paths resolve to null:** the referenced request/identity data is missing.

---

## Template substitution

Step configuration values (`With.*`) support `{{path}}` placeholders that are resolved against the
request during plan build. For example:

```powershell
IdentityKey = '{{Request.IdentityKeys.sAMAccountName}}'
Message     = 'User {{Request.DesiredState.DisplayName}} is joining.'

# Backslash is a literal character — domain paths work without extra escaping:
IdentityKey = 'DOMAIN\{{Request.IdentityKeys.sAMAccountName}}'
```

See [Reference: Template Substitution](../reference/specs/template-substitution.md) for the full
syntax, allowed roots, escaping rules, and validation behaviour.

---

## Reference

For full definitions and reference, see:

- [Reference](../reference/intro-reference.md)
- [Reference: Step Types](../reference/steps.md)
- [Reference: Providers](../reference/providers.md)

---

## Next steps

- Map external systems: [Providers](providers.md)
- Review and export plans: [Plan Export](plan-export.md) (e.g. for CI systems)

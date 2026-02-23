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

### Step execution controls

Each step supports several optional execution control properties:

| Property | Evaluated at | Purpose |
|---|---|---|
| `Condition` | Plan time | Include or skip the step based on request/intent data. |
| `Preconditions` | Execution time (runtime) | Guard the step against stale or unsafe state immediately before it runs. See [Runtime Preconditions](preconditions.md). |
| `OnFailureSteps` | After failure (workflow-level) | Cleanup/rollback steps run after a primary step fails. |

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
request during plan build (`New-IdlePlan`). Multiple placeholders may appear in a single value.

```powershell
IdentityKey = '{{Request.IdentityKeys.sAMAccountName}}'
DisplayName = '{{Request.Intent.GivenName}}'
Message     = 'User {{Request.Intent.DisplayName}} is joining.'
```

### Allowed roots

For security, only these path roots are permitted:

| Root | Description |
| ---- | ----------- |
| `Request.Intent.*` | Caller-provided action inputs |
| `Request.Context.*` | Read-only associated context (host/resolver-provided) |
| `Request.IdentityKeys.*` | Identifiers of the target identity |
| `Request.LifecycleEvent` | Lifecycle event type (e.g. `Joiner`) |
| `Request.CorrelationId` | Stable correlation identifier |
| `Request.Actor` | Originator of the request |

### Pure vs. mixed placeholders

A value containing **only** a single placeholder preserves the resolved type (bool, int, datetime, guid, string):

```powershell
# Resolves to the actual [bool] value, not the string "True"
Enabled = '{{Request.Intent.IsEnabled}}'
```

A value with surrounding text always produces a **string**:

```powershell
Message = 'Account for {{Request.Intent.DisplayName}} created.'
```

### Backslash and special characters

Backslash (`\`) is a **literal character** in template strings and requires no escaping.
Windows-style paths and domain-qualified names work as-is:

```powershell
# \ is kept as-is; only the placeholder is substituted
IdentityKey = 'DOMAIN\{{Request.IdentityKeys.sAMAccountName}}'
# → e.g. 'DOMAIN\jdoe'
```

### Escaping a literal `{{`

To include a literal `{{` in the output, prefix it with `\`. The escape is applied whenever
`\{{` is **not** immediately followed by a valid allowed-root template path and `}}`:

```powershell
# \{{ not followed by a valid path+}} → literal {{ in output
Value = 'Literal \{{ braces here'
# → 'Literal {{ braces here'

# \{{ followed by an invalid/disallowed path → also escaped (literal {{ in output)
Value = '\{{Request.InvalidRoot}}'
# → '{{Request.InvalidRoot}}'
```

Summary of backslash behaviour:

| Input | Result |
| ----- | ------ |
| `DOMAIN\{{Request.IdentityKeys.sAMAccountName}}` | `DOMAIN\jdoe` — `\` literal, valid template resolved |
| `Literal \{{ braces here` | `Literal {{ braces here` — escape applied |
| `\{{Request.InvalidRoot}}` | `{{Request.InvalidRoot}}` — invalid root, escape applied |
| `Literal \{{ and {{Request.Intent.Name}}` | `Literal {{ and TestName` — escape + template |

### Validation

During plan build, IdLE validates every template value:

- **Unbalanced braces** — mismatched `{{`/`}}` pairs throw a syntax error.
- **Invalid path** — paths must use dot-separated identifiers (letters, numbers, underscores).
- **Disallowed root** — paths outside the allowlist throw a security error.
- **Null or missing value** — if the resolved path does not exist, an error is thrown.
- **Non-scalar value** — resolving to a hashtable or array is not allowed.

---

## Reference

For full definitions and reference, see:

- [Reference](../reference/intro-reference.md)
- [Reference: Step Types](../reference/steps.md)
- [Reference: Providers](../reference/providers.md)

---

## Next steps

- Add runtime safety guards: [Runtime Preconditions](preconditions.md)
- Map external systems: [Providers](providers.md)
- Review and export plans: [Plan Export](plan-export.md) (e.g. for CI systems)

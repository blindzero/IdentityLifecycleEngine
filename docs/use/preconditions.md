---
title: Runtime Preconditions
sidebar_label: Runtime Preconditions
---

Runtime Preconditions are **read-only execution guards** evaluated immediately before a step runs.
They protect against stale plans: when time passes between plan creation and execution, external
state may have changed. Preconditions check live (or request-context) data at execution time and
stop the run before an unsafe action is taken.

:::info Planning-time vs. runtime
`Condition` is evaluated at **planning time** and controls whether a step is included in the plan
(`Status = Planned | NotApplicable`). Preconditions are evaluated at **execution time**, after the
plan is built, immediately before each step runs. This keeps planning deterministic while enabling
safety guards.
:::

---

## When to use preconditions

Use preconditions when:

- The validity of a step depends on **current state** that may change after plan creation.
- A policy or compliance rule must be checked **live** before an action is allowed to proceed.
- You want to surface a structured, human-readable message to an operator when a gate fails.

**Example — BYOD policy:**

Before disabling an identity, the system should verify that company data has been wiped from any
BYOD (Bring Your Own Device) device. If the wipe confirmation is missing, execution must stop with
a `Blocked` outcome and a message instructing the operator to perform the wipe manually.

---

## Schema

Add these optional properties to a workflow step definition:

| Property | Type | Required | Description |
|---|---|---|---|
| `Preconditions` | `Array[Condition]` | No | One or more condition nodes (same DSL as `Condition`). All must pass for the step to execute. |
| `OnPreconditionFalse` | `String` | No | Behavior when a precondition fails. `Blocked` (default) or `Fail`. |
| `PreconditionEvent` | `Hashtable` | No | Structured event emitted when a precondition fails. |

### PreconditionEvent schema

| Key | Type | Required | Description |
|---|---|---|---|
| `Type` | `String` | **Yes** | Event type string (for example: `ManualActionRequired`). |
| `Message` | `String` | **Yes** | Human-readable description of the required action. |
| `Data` | `Hashtable` | No | Optional key-value payload. Must not contain secrets. |

---

## Example

```powershell
@{
  Name           = 'Leaver'
  LifecycleEvent = 'Leaver'

  Steps          = @(
    @{
      Name = 'DisableIdentity'
      Type = 'IdLE.Step.DisableIdentity'
      With = @{
        Provider    = 'Identity'
        IdentityKey = '{{Request.IdentityKeys.sAMAccountName}}'
      }

      # Runtime guard: only execute if BYOD wipe is confirmed.
      Preconditions      = @(
        @{
          Equals = @{
            Path  = 'Request.Context.Byod.WipeConfirmed'
            Value = 'true'
          }
        }
      )
      OnPreconditionFalse = 'Blocked'
      PreconditionEvent   = @{
        Type    = 'ManualActionRequired'
        Message = 'Perform Intune retire / wipe company data for BYOD device before disabling the identity.'
        Data    = @{
          Reason = 'BYOD wipe not confirmed'
        }
      }
    }
  )
}
```

---

## Condition DSL

Each entry in `Preconditions` uses the same **declarative condition DSL** as the `Condition`
property. Supported operators:

| Operator | Shape | Description |
|---|---|---|
| `Equals` | `@{ Path = '...'; Value = '...' }` | True when the resolved path equals the value (string comparison). |
| `NotEquals` | `@{ Path = '...'; Value = '...' }` | True when the resolved path does not equal the value. |
| `Exists` | `'path'` or `@{ Path = '...' }` | True when the resolved path is non-null. |
| `In` | `@{ Path = '...'; Values = @(...) }` | True when the resolved path value is in the list. |
| `All` | `@{ All = @( ... ) }` | True when all child conditions are true (AND). |
| `Any` | `@{ Any = @( ... ) }` | True when at least one child condition is true (OR). |
| `None` | `@{ None = @( ... ) }` | True when no child conditions are true (NOR). |

### Path resolution

Paths are resolved against the **execution-time context**, which includes:

| Root | Description |
|---|---|
| `Plan.*` | The plan object (e.g. `Plan.LifecycleEvent`). |
| `Request.*` | The lifecycle request, including `Request.Intent.*`, `Request.Context.*`, `Request.IdentityKeys.*`. |

A leading `context.` prefix is ignored for readability (e.g. `context.Request.Intent.Department`
resolves identically to `Request.Intent.Department`).

---

## Blocked vs. Failed outcomes

| Outcome | `OnPreconditionFalse` | Meaning | OnFailureSteps triggered? |
|---|---|---|---|
| `Blocked` | `Blocked` (default) | A policy or precondition gate stopped execution. Not a technical failure. | **No** |
| `Failed` | `Fail` | Treated as a genuine failure (same semantics as a step error). | **Yes** |

### Execution result

When a step is `Blocked`:

- `result.Status` is `'Blocked'`.
- `result.Steps[n].Status` is `'Blocked'` for the blocking step.
- `result.OnFailure.Status` is `'NotRun'` (OnFailureSteps do not execute).
- A `StepPreconditionFailed` engine event is always emitted.
- If `PreconditionEvent` is configured, an additional event of the declared `Type` is also emitted.

When `OnPreconditionFalse = 'Fail'`:

- `result.Status` is `'Failed'`.
- `result.Steps[n].Status` is `'Failed'` with `Error = 'Precondition check failed.'`.
- `OnFailureSteps` run (same behavior as any other step failure).

---

## Events emitted on precondition failure

The engine always emits a `StepPreconditionFailed` event containing:

| Field | Value |
|---|---|
| `Type` | `StepPreconditionFailed` |
| `StepName` | The name of the blocked step. |
| `Data.StepType` | The step type identifier. |
| `Data.OnPreconditionFalse` | `Blocked` or `Fail`. |

If `PreconditionEvent` is configured, an additional event is emitted with:

| Field | Value |
|---|---|
| `Type` | The configured `PreconditionEvent.Type`. |
| `Message` | The configured `PreconditionEvent.Message`. |
| `StepName` | The name of the blocked step. |
| `Data` | The configured `PreconditionEvent.Data` (if provided). |

:::warning Log safety
`PreconditionEvent.Data` is surfaced as a structured event and may be forwarded to audit sinks.
Do **not** include secrets, credentials, or personal data in `Data`.
:::

---

## Backward compatibility

Steps without `Preconditions` behave exactly as before. Adding preconditions to a step does not
affect any other steps.

---

## Reference

- [Condition DSL reference](../reference/specs/conditions.md) (shared between `Condition` and `Preconditions`)
- [Steps reference](../reference/steps.md)
- [Concepts: Plan → Execute separation](../about/concepts.md)

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
| `OnPreconditionFalse` | `String` | No | Behavior when a precondition fails. `Blocked` (default), `Fail`, or `Continue`. |
| `PreconditionEvent` | `Hashtable` | No | Structured event emitted when a precondition fails. |

`Precondition` (singular) is accepted as a deprecated alias for one condition node. Do not define both `Precondition` and `Preconditions` on the same step; use `Preconditions` for new workflows.

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
      # Note: the condition DSL compares values as strings.
      # Request.Context.Byod.WipeConfirmed must be the string 'true' (e.g. set by a ContextResolver).
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

## Blocked vs. Failed vs. Continue outcomes

| Outcome | `OnPreconditionFalse` | Meaning | Stops execution? | OnFailureSteps triggered? |
|---|---|---|---|---|
| `Blocked` | `Blocked` (default) | A policy or precondition gate stopped execution. Not a technical failure. | **Yes** | **No** |
| `Failed` | `Fail` | Treated as a genuine failure (same semantics as a step error). | **Yes** | **Yes** |
| `PreconditionSkipped` | `Continue` | Emits observability events and skips the step; subsequent steps run normally. | **No** | **No** |

### Execution result — Blocked

When a step is `Blocked`:

- `result.Status` is `'Blocked'`.
- `result.Steps[n].Status` is `'Blocked'` for the blocking step.
- `result.OnFailure.Status` is `'NotRun'` (OnFailureSteps do not execute).
- A `StepPreconditionFailed` engine event is always emitted.
- A `StepBlocked` engine event is emitted for the blocked step.
- If `PreconditionEvent` is configured, an additional event of the declared `Type` is also emitted.

### Execution result — Fail

When `OnPreconditionFalse = 'Fail'`:

- `result.Status` is `'Failed'`.
- `result.Steps[n].Status` is `'Failed'` with `Error = 'Precondition check failed.'`.
- `OnFailureSteps` run (same behavior as any other step failure).
- A `StepPreconditionFailed` engine event is always emitted.
- A `StepFailed` engine event is emitted (matching the format of regular step failure events).
- If `PreconditionEvent` is configured, an additional event of the declared `Type` is also emitted.

### Execution result — Continue

When `OnPreconditionFalse = 'Continue'`:

- `result.Status` is `'Completed'` (unless a subsequent step fails for another reason).
- `result.Steps[n].Status` is `'PreconditionSkipped'` for the skipped step.
- Subsequent steps execute as normal.
- A `StepPreconditionFailed` engine event is always emitted for observability.
- If `PreconditionEvent` is configured, an additional event of the declared `Type` is also emitted.

Use `Continue` when a precondition failure is advisory rather than blocking — for example, to emit
an audit event noting that an optional step was skipped due to a policy condition, while allowing
the rest of the workflow to complete.

---

## Events emitted on precondition failure

| Event type | `OnPreconditionFalse` modes | Description |
|---|---|---|
| `StepPreconditionFailed` | All (`Blocked`, `Fail`, `Continue`) | Always emitted. Contains `StepType`, `Index`, `OnPreconditionFalse`. |
| `StepBlocked` | `Blocked` | Emitted when the step outcome is `Blocked`. Contains `StepType`, `Index`. |
| `StepFailed` | `Fail` | Emitted when the step outcome is `Failed`. Contains `StepType`, `Index`, `Error`. |
| Configured `PreconditionEvent.Type` | All (if `PreconditionEvent` configured) | Caller-defined event. |

### StepPreconditionFailed event

| Field | Value |
|---|---|
| `Type` | `StepPreconditionFailed` |
| `StepName` | The name of the affected step. |
| `Data.StepType` | The step type identifier. |
| `Data.Index` | The step index in the plan. |
| `Data.OnPreconditionFalse` | `Blocked`, `Fail`, or `Continue`. |

### PreconditionEvent (caller-configured)

If `PreconditionEvent` is configured, an additional event is emitted with:

| Field | Value |
|---|---|
| `Type` | The configured `PreconditionEvent.Type`. |
| `Message` | The configured `PreconditionEvent.Message`. |
| `StepName` | The name of the affected step. |
| `Data` | The configured `PreconditionEvent.Data` (if provided). |

:::warning Log safety
`PreconditionEvent.Data` is surfaced as a structured event and may be forwarded to audit sinks.
Do **not** include secrets, credentials, or personal data in `Data`.
:::

:::note String comparison
The condition DSL always compares values as **strings** (for example, boolean `$true` becomes `'True'`).
Ensure context values are stored as strings when using `Equals` or `In` operators.
:::

---

## Backward compatibility

Steps without `Preconditions` behave exactly as before. Adding preconditions to a step does not
affect any other steps.

---

## Reference

- [Steps reference](../../reference/steps.md)
- [Concepts: Plan → Execute separation](../../about/concepts.md)

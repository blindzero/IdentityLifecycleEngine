---
title: Preconditions
sidebar_label: Preconditions
---

# Preconditions

## What are Preconditions?

Preconditions guard **step execution**.

- Evaluated during execution
- Do not change plan shape
- Controlled via `OnPreconditionFalse`

Think of **Preconditions** as runtime safety checks. \
They protect execution but do not affect planning.

---

## ⚠️ Context Resolvers vs Templates vs Conditions vs Preconditions

:::warning Do not confuse these concepts
**[Context Resolvers](./context-resolver.md)** populate `Request.Context.*` during **planning**.  
**[Template Substitution](./templates.md)** uses allowlisted `Request.*` values (such as `Request.Context.*`) to build strings.  
**[Conditions](./conditions.md)** decide step applicability during **planning** (`NotApplicable`).  
**Preconditions** guard step behavior during **execution** (`Blocked` / `Fail` / `Continue`).
:::

| Precondition | Condition |
|--------------|------------|
| Execution time | Planning time |
| Controls runtime behavior | Marks step `NotApplicable` |
| Affects execution result | Affects plan shape |

---

## Full Example

```powershell
@{
  Name = 'Disable existing identity'
  Type = 'IdLE.Step.DisableIdentity'

  Precondition = @{
    Equals = @{ Path = 'Request.Context.IdentityExists'; Value = 'True' }
  }

  OnPreconditionFalse = 'Continue'
}
```

### Explanation

The step executes only if:

- `IdentityExists` equals `True`

If the precondition evaluates to false:

- `Continue` → step is skipped
- `Fail` → execution fails
- `Continue` → execution continues

---

## Condition DSL

:::tip Preconditions use the same **Condition DSL** as Conditions.
For the complete DSL reference, see: [Conditions → Condition DSL](./conditions.md)
:::

---

## Schema

Add these optional properties to a workflow step definition:

| Property | Type | Required | Description |
|---|---|---|---|
| `Precondition` | `Condition` | No | One condition node (same DSL as `Condition`). It must evaluate to true for the step to execute. |
| `OnPreconditionFalse` | `String` | No | Behavior when a precondition fails. `Blocked` (default), `Fail`, or `Continue`. |
| `PreconditionEvent` | `Hashtable` | No | Structured event emitted when a precondition fails. |

### PreconditionEvent schema

| Key | Type | Required | Description |
|---|---|---|---|
| `Type` | `String` | **Yes** | Event type string (for example: `ManualActionRequired`). |
| `Message` | `String` | **Yes** | Human-readable description of the required action. |
| `Data` | `Hashtable` | No | Optional key-value payload. Must not contain secrets. |

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

## Common Patterns

### Guard destructive operations (Skip if not safe)
Use preconditions when:

- The validity of a step depends on **current state** that may change after plan creation.
- A policy or compliance rule must be checked **live** before an action is allowed to proceed.
- You want to surface a structured, human-readable message to an operator when a gate fails.

**Example — BYOD policy:**

Before disabling an identity, the system should verify that company data has been wiped from any
BYOD (Bring Your Own Device) device. If the wipe confirmation is missing, execution must stop with
a `Blocked` outcome and a message instructing the operator to perform the wipe manually.

### Fail fast if a mandatory prerequisite is missing
```powershell
      # Runtime guard: only execute if BYOD wipe is confirmed.
      # Note: the condition DSL compares values as strings.
      # Request.Context.Byod.WipeConfirmed must be the string 'true' (e.g. set by a ContextResolver).
      Precondition       = @{
        All = @(
        @{
          Equals = @{
            Path  = 'Request.Context.Byod.WipeConfirmed'
            Value = 'true'
          }
        }
        )
      }
      OnPreconditionFalse = 'Blocked'
      PreconditionEvent   = @{
        Type    = 'ManualActionRequired'
        Message = 'Perform Intune retire / wipe company data for BYOD device before disabling the identity.'
        Data    = @{
          Reason = 'BYOD wipe not confirmed'
        }
      }
```

---

## Troubleshooting

### Step is skipped unexpectedly
`Precondition` uses the same **declarative condition DSL** as the `Condition`
property. Supported operators:

- Check `OnPreconditionFalse`. If it is set to `Continue`, a false precondition will skip execution by design.
- Validate that the precondition `Path` resolves to the expected runtime value.

### Step fails due to precondition

- If `OnPreconditionFalse = 'Fail'`, the step will fail intentionally when the precondition is false.
- Ensure required request values are prepared before execution (often host-side request preparation).

### Precondition seems correct but still evaluates false

- Remember comparisons are string-based. Normalize values (especially booleans) consistently (for example `'True'` / `'False'`).
- Confirm you are using the correct path (`Plan.*`, `Request.*`).

### Where is the DSL documented?

Preconditions use the same Condition DSL as Conditions. For the complete DSL reference, see:  
[Conditions → Condition DSL](./conditions)

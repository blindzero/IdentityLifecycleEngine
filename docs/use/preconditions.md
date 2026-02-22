---
title: Runtime Preconditions
sidebar_label: Runtime Preconditions
---

Runtime preconditions are **read-only execution guards** evaluated immediately before each step
runs. They protect against the safety gap that occurs when time passes between plan creation and
plan execution — external state may have changed since the plan was built.

Planning remains deterministic: `Condition` is still evaluated at plan-build time to set step
status. Runtime preconditions add a second, execution-time layer of safety without changing the
plan artifact.

---

## When to use preconditions

Use runtime preconditions when:

- Policy requires a live check before an action executes (e.g., verify a device is wiped before
  disabling an identity).
- The correctness of a step depends on state that may have changed after the plan was built.
- You want a structured, auditable signal (event) when a safety guard prevents execution.

Do **not** use preconditions to replace planning-time conditions; use `Condition` for that.

---

## Workflow schema

Three optional keys can be added to any step definition:

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `Preconditions` | `array` of condition nodes | `@()` | Declarative conditions evaluated at execution time. All must pass. Uses the same schema as `Condition`. |
| `OnPreconditionFalse` | `'Blocked'` or `'Fail'` | `'Blocked'` | Outcome when any precondition fails. |
| `PreconditionEvent` | `hashtable` | `$null` | Optional structured event emitted when a precondition fails. |

### PreconditionEvent schema

| Key | Type | Description |
|-----|------|-------------|
| `Type` | `string` | Event type (e.g., `ManualActionRequired`). |
| `Message` | `string` | Human-readable description of the required action. |
| `Data` | `hashtable` | Structured key-value payload (log-safe, no secrets). |

---

## Example: BYOD policy guard

The following snippet shows the `DisableIdentity` step guarded by a BYOD policy precondition.
If the user is still a member of a BYOD group (checked via `Plan.Request` state snapshot), the
step is blocked and a structured event is emitted.

```powershell
@{
  Name           = 'Leaver - Standard'
  LifecycleEvent = 'Leaver'

  Steps          = @(
    @{
      Name                = 'DisableIdentity'
      Type                = 'IdLE.Step.DisableIdentity'
      With                = @{ Provider = 'Identity' }

      Preconditions       = @(
        @{
          # Pass only when WipeConfirmed is true OR user is not a BYOD member.
          # In a real workflow this path resolves from the request input.
          Equals = @{
            Path  = 'Plan.Request.DesiredState.Byod.WipeConfirmed'
            Value = 'true'
          }
        }
      )
      OnPreconditionFalse = 'Blocked'
      PreconditionEvent   = @{
        Type    = 'ManualActionRequired'
        Message = 'User is in a BYOD group. Perform Intune retire / wipe before disabling identity.'
        Data    = @{
          Policy  = 'BYOD'
          StepRef = 'DisableIdentity'
        }
      }
    }
  )
}
```

---

## Engine behavior

1. **Plan creation is unchanged.** `Condition` is evaluated at plan-build time. Preconditions are stored in the plan but not evaluated yet.

2. **At execution time**, before invoking each `Planned` step:
   - All items in `Preconditions` are evaluated against the execution context.
   - If all pass → step executes normally.
   - If any fails:
     - If `PreconditionEvent` is configured, the structured event is emitted first.
     - If `OnPreconditionFalse = 'Blocked'` (default):
       - Step outcome is `Blocked`.
       - Run status is `Blocked`.
       - A `StepBlocked` engine event is emitted.
       - Execution stops; subsequent steps do not run.
     - If `OnPreconditionFalse = 'Fail'`:
       - Step outcome is `Failed`.
       - Run status is `Failed`.
       - A `StepFailed` engine event is emitted.
       - Execution stops; `OnFailureSteps` run if configured.

3. **Steps without `Preconditions` behave exactly as before** (full backward compatibility).

---

## Evaluation context paths

Precondition nodes use the same path syntax as `Condition`. At execution time the context root is
the execution context, which exposes:

| Path prefix | Points to |
|-------------|-----------|
| `Plan.*` | The plan object (includes `Request`, `LifecycleEvent`, etc.) |
| `Plan.Request.*` | The lifecycle request snapshot |
| `Plan.Request.DesiredState.*` | Desired state from the request |
| `Plan.Request.IdentityKeys.*` | Identity keys from the request |
| `CorrelationId` | Run correlation ID |
| `Actor` | Actor from the request |

---

## Related

- [Concepts: Planning vs. Execution](../about/concepts.md)
- [Workflows & Steps](workflows.md)
- [Reference: Conditions](../reference/conditions.md)

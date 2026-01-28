---
title: Steps
sidebar_label: Steps
---

# Steps

Steps are reusable plugins that define how IdLE should converge state.

A step typically has two parts:

- **Test**: plan data-only actions
- **Invoke**: execute planned actions

## Design goals

Steps should be:

- idempotent (converge towards the desired state)
- deterministic (same inputs produce the same plan)
- provider-agnostic (use provider contracts, not direct system calls)
- safe for preview (planning must not change external state)

## Inputs

Steps receive inputs from the workflow under `Inputs` and may reference:

- `Request.*`
- `State.*`
- `Policy.*` (optional root, host-defined)

Avoid executing code from configuration. Keep inputs data-only.

## Outputs

Steps may write to `State.*` only, and only to declared output paths.
This prevents hidden coupling between steps.

## Eventing

Steps may emit **structured events** for progress and audit.

The engine provides a stable, object-based contract on the execution context:

- `Context.EventSink.WriteEvent(Type, Message, StepName, Data)`

Notes:

- `Type` is a short string (for example: `Custom`, `Debug`).
- `Message` is a human-readable message.
- `StepName` should be the current step name (if available).
- `Data` is an optional hashtable for structured details.

Example:

```powershell
$Context.EventSink.WriteEvent(
  'Custom',
  'Ensured Department attribute.',
  $Step.Name,
  @{ Provider = 'Identity'; Attribute = 'Department' }
)
```

Security and portability:

- Steps must never execute code from configuration.
- Steps must not assume a specific host UI.
- Hosts can optionally stream events via `Invoke-IdlePlan -EventSink <object>`,
  but **ScriptBlock sinks are not supported**.

## Error behavior

### Primary steps (fail-fast)

IdLE uses a **fail-fast execution model** for primary workflow steps:

- A failing step stops plan execution immediately
- Subsequent primary steps are not executed
- Results and events capture what happened up to the failure

### OnFailureSteps (best-effort)

When primary steps fail, workflows can define **OnFailureSteps** for cleanup or rollback.

OnFailureSteps are executed in **best-effort mode**:

- Each OnFailure step is attempted regardless of previous OnFailure step failures
- OnFailure step failures do not stop execution of remaining OnFailure steps
- The overall execution status remains 'Failed' even if all OnFailure steps succeed

**Execution result structure:**

```powershell
$result.Status                # 'Failed' when primary steps fail
$result.Steps                 # Array of primary step results (only executed steps)
$result.OnFailure.Status      # 'NotRun', 'Completed', or 'PartiallyFailed'
$result.OnFailure.Steps       # Array of OnFailure step results
```

**OnFailure status values:**

- `NotRun`: No primary steps failed, OnFailure steps were not executed
- `Completed`: All OnFailure steps succeeded
- `PartiallyFailed`: At least one OnFailure step failed, but execution continued

For details on declaring OnFailureSteps, see [Workflows](workflows.md).

## Built-in steps (starter pack)

IdLE ships with a small set of built-in steps to keep demos and tests frictionless:

- **IdLE.Step.EnsureAttribute**: converges an identity attribute to the desired value using `With.IdentityKey`, `With.Name`, and `With.Value`. Requires a provider with `EnsureAttribute` and usually the `IdLE.Identity.Attribute.Ensure` capability.
- **IdLE.Step.EnsureEntitlement**: converges an entitlement assignment to `Present` or `Absent` using `With.IdentityKey`, `With.Entitlement` (Kind + Id + optional DisplayName), `With.State`, and optional `With.Provider` (default `Identity`). Requires provider methods `ListEntitlements` plus `GrantEntitlement` or `RevokeEntitlement` and typically the capabilities `IdLE.Entitlement.List` plus `IdLE.Entitlement.Grant|Revoke`.

## Related

- [Workflows](workflows.md)
- [Providers](providers.md)
- [Architecture](../about/architecture.md)

## Security notes

- Steps emit events via `Context.EventSink.WriteEvent(...)`.
- Step handlers are referenced by function name (string) in the step registry.
- ScriptBlock handlers are not supported as a secure default.

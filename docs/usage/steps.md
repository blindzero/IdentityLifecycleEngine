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

IdLE uses a fail-fast execution model in V1:

- a failing step stops plan execution
- results and events capture what happened

## Built-in steps (starter pack)

IdLE ships with a small set of built-in steps to keep demos and tests frictionless:

- **IdLE.Step.EnsureAttribute**: converges an identity attribute to the desired value using `With.IdentityKey`, `With.Name`, and `With.Value`. Requires a provider with `EnsureAttribute` and usually the `Identity.Attribute.Ensure` capability.
- **IdLE.Step.EnsureEntitlement**: converges an entitlement assignment to `Present` or `Absent` using `With.IdentityKey`, `With.Entitlement` (Kind + Id + optional DisplayName), `With.State`, and optional `With.Provider` (default `Identity`). Requires provider methods `ListEntitlements` plus `GrantEntitlement` or `RevokeEntitlement` and typically the capabilities `IdLE.Entitlement.List` plus `IdLE.Entitlement.Grant|Revoke`.

## Related

- [Workflows](workflows.md)
- [Providers](providers.md)
- [Architecture](../advanced/architecture.md)

## Security notes

- Steps emit events via `Context.EventSink.WriteEvent(...)`.
- Step handlers are referenced by function name (string) in the step registry.
- ScriptBlock handlers are not supported as a secure default.

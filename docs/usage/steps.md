# IdentityLifecycleEngine (IdLE) - Steps

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

## Error behavior

IdLE uses a fail-fast execution model in V1:

- a failing step stops plan execution
- results and events capture what happened

## Related

- [Workflows](workflows.md)
- [Providers](providers.md)
- [Architecture](../advanced/architecture.md)

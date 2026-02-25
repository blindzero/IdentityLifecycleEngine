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

## ⚠️ Preconditions vs Conditions

:::warning Do not confuse Preconditions and Conditions
Preconditions are evaluated during **execution**.  
Conditions are evaluated during **planning**.  

See: [Conditions](./conditions)
:::

| Preconditions | Conditions |
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

  Preconditions = @{
    Equals = @{ Path = 'Request.Context.IdentityExists'; Value = 'True' }
  }

  OnPreconditionFalse = 'Skip'
}
```

### Explanation

The step executes only if:

- `IdentityExists` equals `True`

If the precondition evaluates to false:

- `Skip` → step is skipped
- `Fail` → execution fails
- `Continue` → execution continues

---

## Condition DSL

:::tip Preconditions use the same **Condition DSL** as Conditions.
For the complete DSL reference, see: [Conditions → Condition DSL](./conditions)
:::

---

## Common Patterns

### Guard destructive operations (Skip if not safe)

```powershell
Preconditions = @{ Equals = @{ Path = 'Request.Context.IdentityExists'; Value = 'True' } }
OnPreconditionFalse = 'Skip'
```

### Fail fast if a mandatory prerequisite is missing

```powershell
Preconditions = @{ Exists = 'Request.IdentityKeys.EmployeeId' }
OnPreconditionFalse = 'Fail'
```

### Continue but record the outcome

Use this for optional operations where you prefer to continue execution but still want the step result to show the precondition outcome.

```powershell
Preconditions = @{ Exists = 'Request.Context.OptionalValue' }
OnPreconditionFalse = 'Continue'
```

### Only execute for specific lifecycle events

```powershell
Preconditions = @{ In = @{ Path = 'Plan.LifecycleEvent'; Values = @('Joiner','Mover') } }
OnPreconditionFalse = 'Skip'
```

---

## Troubleshooting

### Step is skipped unexpectedly

- Check `OnPreconditionFalse`. If it is set to `Skip`, a false precondition will skip execution by design.
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

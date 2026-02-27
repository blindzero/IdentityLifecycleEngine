---
title: Conditions
sidebar_label: Conditions
---

# Conditions

## What are Conditions?

Conditions control **step applicability during planning**.

- Evaluated while the plan is being built
- If the condition evaluates to `false`, the step becomes `NotApplicable`
- Conditions shape the plan, not execution

Think of **Conditions** as a *planning-time filter*. \
They decide whether a step becomes part of the executable plan.

---

## ⚠️ Context Resolvers vs Templates vs Conditions vs Preconditions

:::warning Do not confuse these concepts
**[Context Resolvers](./context-resolver.md)** populate `Request.Context.*` during **planning**.  
**[Template Substitution](./templates.md)** consumes `Request.*` values to build strings.  
**Conditions** decide step applicability during **planning** (`NotApplicable`).  
**[Preconditions](./preconditions.md)** guard step behavior during **execution** (`Blocked` / `Fail` / `Continue`).
:::

| Conditions | Preconditions |
|------------|--------------|
| Planning time | Execution time |
| Marks step `NotApplicable` | Controls runtime behavior |
| Affects plan shape | Affects execution flow |

---

## Full Example

```powershell
@{
  Name = 'Provision EU Joiner'
  Type = 'IdLE.Step.EmitEvent'

  Condition = @{
    All = @(
      @{ Equals = @{ Path = 'Plan.LifecycleEvent'; Value = 'Joiner' } }
      @{ In     = @{ Path = 'Request.Context.Region'; Values = @('EU','DE') } }
      @{ Exists = 'Request.IdentityKeys.EmployeeId' }
    )
  }

  With = @{
    Message = 'Provisioning for EU Joiner'
  }
}
```

### Explanation

The step is applicable only if:

1. The lifecycle event is `Joiner`
2. The region is `EU` or `DE`
3. An `EmployeeId` exists

If any condition evaluates to false, the step is marked as `NotApplicable` during planning.

---

## Condition DSL

Preconditions use the **same DSL** as Conditions.  
This section is the authoritative DSL reference.

### Groups

- `All` — all child conditions must be true (AND)
- `Any` — at least one child condition must be true (OR)
- `None` — none of the child conditions must be true (NOR)

### Operators

#### Equals

```powershell
@{ Equals = @{ Path = 'Plan.LifecycleEvent'; Value = 'Joiner' } }
```

#### NotEquals

```powershell
@{ NotEquals = @{ Path = 'Request.Context.Tenant'; Value = 'DEV' } }
```

#### Exists

```powershell
@{ Exists = 'Request.Context.ManagerUpn' }
```

#### In

```powershell
@{
  In = @{
    Path   = 'Plan.LifecycleEvent'
    Values = @('Joiner','Mover')
  }
}
```

---

## Comparison Semantics

- Comparisons are string-based
- Deterministic evaluation
- Values are converted to string before comparison

---

## Validation Rules

- Each node may contain exactly one operator or group
- Unknown keys cause planning-time errors
- Missing or empty `Path` causes validation errors

---

## Common Patterns

### Only for a lifecycle event

```powershell
Condition = @{ Equals = @{ Path = 'Plan.LifecycleEvent'; Value = 'Leaver' } }
```

### Only if a request field exists

```powershell
Condition = @{ Exists = 'Request.Context.ManagerUpn' }
```

### Allowlist values (In)

```powershell
Condition = @{ In = @{ Path = 'Request.Context.Region'; Values = @('EU','US') } }
```

### Negation (NOT via None)

```powershell
Condition = @{ None = @( @{ Equals = @{ Path = 'Request.Context.Tenant'; Value = 'DEV' } } ) }
```

### Combine multiple checks (All / AND)

```powershell
Condition = @{
  All = @(
    @{ Equals = @{ Path = 'Plan.LifecycleEvent'; Value = 'Joiner' } }
    @{ Exists = 'Request.IdentityKeys.EmployeeId' }
  )
}
```

---

## Troubleshooting

### Step is `NotApplicable` but you expected it to run

- Verify the used `Path` values are correct and exist at planning time (for example `Request.Context.*` vs `Request.IdentityKeys.*`).
- Remember comparisons are string-based. Normalize boolean-like values in the request (for example use `'True'` / `'False'` consistently).

### Planning fails with “Unknown key … in condition node”

Each node may contain exactly one of:

- a group: `All`, `Any`, `None`
- an operator: `Equals`, `NotEquals`, `Exists`, `In`

Any additional keys cause a planning-time validation error.

### Planning fails with “Missing or empty Path”

Operators like `Equals`, `NotEquals`, and `In` require a non-empty `Path`.  
For `Exists`, prefer the short form `Exists = '…'` to avoid shape errors.

### Confusion about “Skipped”

Conditions do not “skip” execution. They decide applicability during planning and mark the step as `NotApplicable`.

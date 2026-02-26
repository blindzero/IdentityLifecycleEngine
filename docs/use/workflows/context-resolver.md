---
title: Context Resolvers
sidebar_label: Context Resolvers
---

## What are Context Resolvers?

Context Resolvers populate **`Request.Context.*` during planning** using **read-only provider capabilities**.

- Resolvers run during **plan build**
- They enrich the request with stable, pre-resolved data (for example an entitlement snapshot)
- They are **data-only** and validated strictly (fail-fast)

This allows **Conditions**, **Preconditions**, and **Template Substitution** to reference values that were resolved once at planning time.

---

## ⚠️ Context Resolvers vs Templates vs Conditions vs Preconditions

:::warning Do not confuse these concepts
**Context Resolvers** populate `Request.Context.*` during **planning**.  
**[Template Substitution](./templates.md)** consumes `Plan` / `Request` / `Workflow` values to build strings.  
**[Conditions](conditions.md)** decide step applicability during **planning** (`NotApplicable`).  
**[Preconditions](./preconditions.md)** guard step behavior during **execution** (`Skip` / `Fail` / `Continue`).
:::

---

## Common Patterns

### Entitlement snapshot (without pattern matching)

Resolve entitlements once during planning:

```powershell
ContextResolvers = @(
    @{
        Capability = 'IdLE.Entitlement.List'
        With       = @{ IdentityKey = '{{Request.IdentityKeys.EmployeeId}}' }
    }
)
```

Then guard on availability:

```powershell
Condition = @{ Exists = 'Request.Context.Identity.Entitlements' }
```

> The current Condition DSL does not support list-membership or pattern operators.
> Membership evaluation requires either host-prepared boolean flags or a future DSL enhancement.

---

## Troubleshooting

- Ensure `ContextResolvers` is defined at workflow root.
- Ensure a provider advertises the requested capability.

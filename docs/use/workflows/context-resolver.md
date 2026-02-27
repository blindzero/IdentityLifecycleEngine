---
title: Context Resolvers
sidebar_label: Context Resolvers
---

## What are Context Resolvers?

Context Resolvers populate **`Request.Context.*` during planning** using **read-only provider capabilities**.

- They run during **plan build**
- They execute before step `Condition` evaluation
- They enrich the request with stable, pre-resolved associated data
- They are strictly validated and fail fast on invalid configuration

Context Resolvers allow **Conditions**, **Preconditions**, and **Template Substitution**
to rely on data that was resolved once during planning.

---

## ⚠️ Context Resolvers vs Templates vs Conditions vs Preconditions

:::warning Do not confuse these concepts
**Context Resolvers** populate `Request.Context.*` during **planning**.  
**[Template Substitution](./templates.md)** consumes `Request.*` values to build strings.  
**[Conditions](conditions.md)** decide step applicability during **planning** (`NotApplicable`).  
**[Preconditions](./preconditions.md)** guard step behavior during **execution** (`Blocked` / `Fail` / `Continue`).
:::

---

## Full Example

A resolver entry is defined at workflow root level:


```powershell
@{
  Name           = 'Joiner - Context Resolver Demo'
  LifecycleEvent = 'Joiner'

  ContextResolvers = @(
    @{
      Capability = 'IdLE.Identity.Read'
      With = @{
        IdentityKey     = '{{Request.IdentityKeys.EmployeeId}}'
        Provider        = 'Identity'        # optional; auto-selected if omitted
        AuthSessionName = 'Tier0'           # optional; requires AuthSessionBroker in Providers
      }
    }

    @{
      Capability = 'IdLE.Entitlement.List'
      With = @{
        IdentityKey = '{{Request.IdentityKeys.EmployeeId}}'
      }
    }
  )

  Steps = @(

    @{
      Name = 'Disable only if identity exists'
      Type = 'IdLE.Step.DisableIdentity'

      Condition = @{
        Exists = 'Request.Context.Identity.Profile'
      }
    }

    @{
      Name = 'Emit audit event'
      Type = 'IdLE.Step.EmitEvent'

      With = @{
        Message = 'Disabled identity {{Request.Context.Identity.Profile.DisplayName}}'
      }
    }
  )
}
```

### Keys

- `Capability` (required)  
  A permitted read-only capability.

- `With` (hashtable, optional — required in practice, as capabilities need at least `IdentityKey`)  
  Inputs required by the capability. Template substitution is supported.

  | `With` key | Type | Required | Description |
  |---|---|---|---|
  | `IdentityKey` | `string` | Per capability | Required by `IdLE.Identity.Read` and `IdLE.Entitlement.List`. |
  | `Provider` | `string` | No | Provider alias. If omitted, IdLE auto-selects a provider advertising the capability. Ambiguity (multiple providers matching) is a fail-fast error. |
  | `AuthSessionName` | `string` | No | Named auth session to acquire via `AuthSessionBroker`. Requires an `AuthSessionBroker` entry in `Providers`. |
  | `AuthSessionOptions` | `hashtable` | No | Options passed to `AuthSessionBroker.AcquireAuthSession`. Must be a hashtable. ScriptBlocks are rejected. |

Output paths are predefined and cannot be changed.

---

## Common Patterns

### Resolve once, use everywhere

Resolve identity or entitlements once and reuse the result in:

- Conditions
- Preconditions
- Templates

Example:

```powershell
Condition = @{ Exists = 'Request.Context.Identity.Profile' }

DisplayName = '{{Request.Context.Identity.Profile.DisplayName}}'
```

### Guard destructive steps

Only perform destructive actions if identity exists:

```powershell
Condition = @{
    Exists = 'Request.Context.Identity.Profile'
}
```

### Entitlement snapshot usage

Resolve entitlements once:

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

---

## Troubleshooting

### Resolver not executed

- Ensure `ContextResolvers` is defined at workflow root.
- Verify correct property name (`ContextResolvers`).

### Capability not permitted

- Only allowlisted read-only capabilities can be used.
- Validation happens during plan build.

### Ambiguous provider

- If multiple providers advertise a capability, specify `With.Provider` explicitly.

### Context value missing

- Verify required `With` parameters.
- Ensure template placeholders resolve correctly.

### Type conflict in context path

- A resolver cannot overwrite an existing path with incompatible type.

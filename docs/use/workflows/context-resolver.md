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

## Context Namespace Structure

Each resolver writes its output to a **provider/auth-scoped source-of-truth path** and updates **engine-defined Views**.

### Source of truth (scoped path)

```
Request.Context.Providers.<ProviderAlias>.<AuthSessionKey>.<CapabilitySubPath>
```

- `<ProviderAlias>` — the provider alias from `With.Provider` (or the auto-selected alias).
- `<AuthSessionKey>` — `Default` when `With.AuthSessionName` is not specified; otherwise the exact name.
- `<CapabilitySubPath>` — the capability-defined sub-path:
  - `IdLE.Entitlement.List` → `Identity.Entitlements`
  - `IdLE.Identity.Read` → `Identity.Profile`

Examples:
- `Request.Context.Providers.Entra.Default.Identity.Entitlements`
- `Request.Context.Providers.Entra.CorpAdmin.Identity.Entitlements`
- `Request.Context.Providers.AD.Default.Identity.Entitlements`
- `Request.Context.Providers.Identity.Default.Identity.Profile`

### Views (engine-defined aggregations)

For capabilities with defined view semantics, the engine builds deterministic Views after each resolver:

| View | Path | Description |
|---|---|---|
| Global view | `Request.Context.Views.<CapabilitySubPath>` | Merged from all providers and auth sessions. |
| Provider view | `Request.Context.Views.Providers.<ProviderAlias>.<CapabilitySubPath>` | Merged for one provider across all auth sessions. |

Currently only `IdLE.Entitlement.List` has defined view semantics.

Examples:
- `Request.Context.Views.Identity.Entitlements` — entitlements from **all** providers and sessions merged
- `Request.Context.Views.Providers.Entra.Identity.Entitlements` — Entra entitlements only

### Step-relative Current alias (execution-time only)

During **precondition** evaluation (execution time), you may use `Request.Context.Current.*` to refer
to the scoped context of the step's own provider and auth session:

```
Request.Context.Current.<CapabilitySubPath>
```

Resolved from `Step.With.Provider` + `Step.With.AuthSessionName` (or `Default`).

> **Restriction:** `Request.Context.Current.*` MUST NOT be used in plan-time `Condition` fields.
> It is only valid in `Precondition` and other execution-time evaluations.

---

## Full Example

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
      # Writes to: Request.Context.Providers.Identity.Tier0.Identity.Profile
    }

    @{
      Capability = 'IdLE.Entitlement.List'
      With = @{
        IdentityKey = '{{Request.IdentityKeys.EmployeeId}}'
        Provider    = 'Identity'
      }
      # Writes to: Request.Context.Providers.Identity.Default.Identity.Entitlements
      # View:      Request.Context.Views.Identity.Entitlements
    }
  )

  Steps = @(

    @{
      Name = 'Disable only if identity exists'
      Type = 'IdLE.Step.DisableIdentity'

      # Reference the scoped source-of-truth path:
      Condition = @{
        Exists = 'Request.Context.Providers.Identity.Tier0.Identity.Profile'
      }
    }

    @{
      Name = 'Emit audit event'
      Type = 'IdLE.Step.EmitEvent'

      With = @{
        Message = 'Disabled identity {{Request.Context.Providers.Identity.Tier0.Identity.Profile.DisplayName}}'
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
  | `Provider` | `string` | No | Provider alias. If omitted, IdLE auto-selects a provider advertising the capability. Ambiguity (multiple providers matching) is a fail-fast error. Also used to determine `<ProviderAlias>` in the scoped path. |
  | `AuthSessionName` | `string` | No | Named auth session key. Becomes `<AuthSessionKey>` in the scoped path. If omitted, `Default` is used. Requires an `AuthSessionBroker` entry in `Providers`. Must be a valid path segment (no dots). |
  | `AuthSessionOptions` | `hashtable` | No | Options passed to `AuthSessionBroker.AcquireAuthSession`. Must be a hashtable. ScriptBlocks are rejected. |

---

## Common Patterns

### Use the global View for "don't care about source"

The most common pattern for entitlements: check or reference entitlements regardless of which provider returned them:

```powershell
# In a Condition:
Condition = @{ Exists = 'Request.Context.Views.Identity.Entitlements' }

# In a NotContains check (member-access enumeration across all providers):
Condition = @{
  NotContains = @{
    Path  = 'Request.Context.Views.Identity.Entitlements.Id'
    Value = 'CN=BreakGlass-Users,OU=Groups,DC=example,DC=com'
  }
}
```

### Use scoped paths for provider-specific checks

When you need to check entitlements only from a specific provider:

```powershell
Condition = @{
  Exists = 'Request.Context.Providers.Entra.Default.Identity.Entitlements'
}
```

### Multi-provider entitlements (no collision)

Use the same capability for multiple providers. Results are kept isolated:

```powershell
ContextResolvers = @(
  @{ Capability = 'IdLE.Entitlement.List'; With = @{ IdentityKey = 'user1'; Provider = 'Entra' } }
  @{ Capability = 'IdLE.Entitlement.List'; With = @{ IdentityKey = 'user1'; Provider = 'AD' } }
)
# Result: Providers.Entra.Default.Identity.Entitlements (Entra-specific)
#         Providers.AD.Default.Identity.Entitlements     (AD-specific)
#         Views.Identity.Entitlements                     (merged, both providers)
```

### Step-relative precondition using Current

Use `Request.Context.Current.*` in a step's `Precondition` to check the scoped context
for that step's own provider without hard-coding the provider alias:

```powershell
@{
  Name         = 'EnsureEntitlement'
  Type         = 'IdLE.Step.EnsureEntitlement'
  With         = @{
    Provider    = 'Entra'
    IdentityKey = '{{Request.IdentityKeys.Id}}'
    Entitlement = @{ Kind = 'Group'; Id = 'sg-all-staff' }
    State       = 'Present'
  }
  # Current resolves to Providers.Entra.Default at execution time (derived from With.Provider)
  Precondition = @{ Exists = 'Request.Context.Current.Identity.Entitlements' }
}
```

### Guard destructive steps

Only perform destructive actions if identity exists:

```powershell
Condition = @{
    Exists = 'Request.Context.Providers.Identity.Default.Identity.Profile'
}
```

---

## Entitlement Source Metadata

Every entitlement entry in a resolved list includes source metadata automatically added by the engine:

| Property | Description |
|---|---|
| `SourceProvider` | The provider alias that returned this entitlement. |
| `SourceAuthSessionName` | The auth session key used (`Default` if no session was specified). |

This enables auditing and per-source filtering when working with merged views.

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
- Remember: scoped path uses `Providers.<Alias>.<AuthKey>.<SubPath>`.
  Views are only available for `IdLE.Entitlement.List`.

### Type conflict in context path

- A resolver cannot overwrite an existing path with incompatible type.
- Pre-existing context keys like `Providers` or `Views` must be hashtables.

### Invalid provider alias or AuthSessionName

- Provider alias and `AuthSessionName` must be valid path segments: `^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$`
- Dots (`.`) are not allowed as they are used as path separators.

### Inspecting resolved context data

When working with complex objects (like entitlements), you may need to inspect the structure to determine the correct path syntax for Conditions or to understand what properties are available.

**Method 1: Inspect the plan object after planning**

```powershell
$plan = New-IdlePlan -WorkflowPath ./workflow.psd1 -Request $req -Providers $providers

# View the entire context structure
$plan.Request.Context | ConvertTo-Json -Depth 5

# View scoped entitlements for a specific provider
$plan.Request.Context.Providers.Identity.Default.Identity.Entitlements | ConvertTo-Json -Depth 2

# View the global merged view
$plan.Request.Context.Views.Identity.Entitlements | ConvertTo-Json -Depth 2
```

**Method 2: Use Format-Table for quick inspection**

```powershell
# After planning, inspect entitlements structure (global view)
$plan.Request.Context.Views.Identity.Entitlements | Format-Table -AutoSize
```

**Method 3: Access individual properties**

```powershell
# Check if entitlements are objects with properties
$plan.Request.Context.Views.Identity.Entitlements[0] | Get-Member
$plan.Request.Context.Views.Identity.Entitlements[0].Id
$plan.Request.Context.Views.Identity.Entitlements[0].SourceProvider
```

**Using discovered structure in Conditions**

Once you know the structure, use member-access enumeration in your condition paths:

```powershell
# Extract Id values from all entitlement objects (global view)
Condition = @{
  NotContains = @{
    Path  = 'Request.Context.Views.Identity.Entitlements.Id'
    Value = 'CN=BreakGlass-Users,OU=Groups,DC=example,DC=com'
  }
}
```

See [Conditions - Member-Access Enumeration](./conditions.md#member-access-enumeration) for details.


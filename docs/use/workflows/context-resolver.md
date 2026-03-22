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
| All providers, all sessions | `Request.Context.Views.<CapabilitySubPath>` | Aggregated from all providers and all auth sessions. |
| One provider, all sessions | `Request.Context.Views.Providers.<ProviderAlias>.<CapabilitySubPath>` | Aggregated for one provider across all its auth sessions. |
| All providers, one session | `Request.Context.Views.Sessions.<AuthSessionKey>.<CapabilitySubPath>` | Aggregated across all providers that ran with the given auth session key. |
| One provider, one session | `Request.Context.Views.Providers.<ProviderAlias>.Sessions.<AuthSessionKey>.<CapabilitySubPath>` | Exactly one provider + one auth session. |

**`IdLE.Entitlement.List`** — list merge (all entries preserved across all contributing providers/sessions):

- `Request.Context.Views.Identity.Entitlements` — all providers, all sessions merged
- `Request.Context.Views.Providers.Entra.Identity.Entitlements` — Entra only, all sessions
- `Request.Context.Views.Sessions.Default.Identity.Entitlements` — all providers, Default session only
- `Request.Context.Views.Providers.Entra.Sessions.CorpAdmin.Identity.Entitlements` — Entra + CorpAdmin session only

**`IdLE.Identity.Read`** — single-object view (last writer wins with deterministic sort order: provider alias asc, then auth key asc):

- `Request.Context.Views.Identity.Profile` — last profile across all providers and sessions
- `Request.Context.Views.Providers.Entra.Identity.Profile` — last profile from Entra (across all sessions)
- `Request.Context.Views.Sessions.Default.Identity.Profile` — last profile from any provider using the Default session
- `Request.Context.Views.Providers.Entra.Sessions.CorpAdmin.Identity.Profile` — exact profile for Entra + CorpAdmin

All profile and entitlement entries include `SourceProvider` and `SourceAuthSessionName` metadata for auditing.

:::info Profile Views are convenience views, not mirrors
Profile Views are **deterministic convenience aggregations**, not direct copies of a specific provider result.  
When multiple `IdLE.Identity.Read` resolvers run (different providers or auth sessions), the aggregated Views reflect the last profile after a stable alphabetical sort (first by provider alias ascending, then by auth session key ascending).

This means `Request.Context.Views.Identity.Profile` may differ from (or be a different object than)
`Request.Context.Providers.<ProviderAlias>.<AuthKey>.Identity.Profile` — that is by design.

**When to use which path:**
- Use `Request.Context.Views.*` when you do not care which provider returned the profile (e.g., "does any profile exist").
- Use `Request.Context.Providers.<ProviderAlias>.<AuthKey>.Identity.Profile` when you need the exact result from a specific provider and session.
:::

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
        Message = 'Disabled identity {{Request.Context.Providers.Identity.Tier0.Identity.Profile.Attributes.DisplayName}}'
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

### Inspecting resolved context data

When working with complex resolver outputs (entitlements, profiles), inspect the plan object directly after calling `New-IdlePlan`. This is the recommended approach during authoring and debugging. **Do not rely on template substitution for this purpose** — template substitution only resolves scalar values and cannot serialize whole objects or lists.

**Inspect the complete context tree:**

```powershell
# Assume you have already built a plan:
# $request   = ...     # build a valid IdLE request
# $providers = @{ ... } # configured provider map
# $plan = New-IdlePlan -WorkflowPath ./workflow.psd1 -Request $request -Providers $providers

# Full context structure (use Depth 8 for deeply nested Views)
$plan.Request.Context | ConvertTo-Json -Depth 8

# Scoped source-of-truth namespace only
$plan.Request.Context.Providers | ConvertTo-Json -Depth 8

# Engine-defined Views only
$plan.Request.Context.Views | ConvertTo-Json -Depth 8
```

**Inspect a specific scoped path:**

```powershell
# Entitlements from one provider
$plan.Request.Context.Providers.Identity.Default.Identity.Entitlements | ConvertTo-Json -Depth 2

# Profile from one provider
$plan.Request.Context.Providers.Identity.Default.Identity.Profile | ConvertTo-Json -Depth 4

# Global merged View
$plan.Request.Context.Views.Identity.Entitlements | ConvertTo-Json -Depth 2
```

**Quick tabular view:**

```powershell
$plan.Request.Context.Views.Identity.Entitlements | Format-Table -AutoSize
```

**Inspect individual properties to understand the path structure:**

```powershell
# Check available properties on the profile object
$plan.Request.Context.Providers.Identity.Default.Identity.Profile | Get-Member

# Access profile attributes — attributes are nested under the Attributes key
$plan.Request.Context.Providers.Identity.Default.Identity.Profile.Attributes

# Check a specific attribute
$plan.Request.Context.Providers.Identity.Default.Identity.Profile.Attributes.DisplayName

# Check an entitlement entry and its source metadata
$plan.Request.Context.Views.Identity.Entitlements[0] | Get-Member
$plan.Request.Context.Views.Identity.Entitlements[0].Id
$plan.Request.Context.Views.Identity.Entitlements[0].SourceProvider
```

**Translating discovered structure to Condition paths:**

```powershell
# Profile attribute — path must include Attributes
Condition = @{
  Like = @{
    Path    = 'Request.Context.Providers.Identity.Default.Identity.Profile.Attributes.DisplayName'
    Pattern = '* (Contractor)'
  }
}

# Entitlement IDs — member-access enumeration extracts all Id values from the list
Condition = @{
  NotContains = @{
    Path  = 'Request.Context.Views.Identity.Entitlements.Id'
    Value = 'CN=BreakGlass-Users,OU=Groups,DC=example,DC=com'
  }
}
```

### Ambiguous provider

- If multiple providers advertise a capability, specify `With.Provider` explicitly.

### Context value missing

- Verify required `With` parameters.
- Ensure template placeholders resolve correctly.
- Remember: scoped path uses `Providers.<Alias>.<AuthKey>.<SubPath>`.
  Views are only available for `IdLE.Entitlement.List` and `IdLE.Identity.Read`.

### Profile path not found in Condition

- Profile attributes are nested under the `Attributes` key, not promoted to top-level.
  Use `...Identity.Profile.Attributes.DisplayName` not `...Identity.Profile.DisplayName`.
- Check the actual structure at plan time: `$plan.Request.Context.Providers.<Alias>.<AuthKey>.Identity.Profile | ConvertTo-Json -Depth 4`

### View differs from source-of-truth path

For `IdLE.Identity.Read`, profile Views are built by **last-writer-wins** with a deterministic sort order (provider alias ascending, then auth session key ascending). This means:

- `Request.Context.Views.Identity.Profile` may contain a profile from a **different** provider/session than a specific scoped path.
- This is expected and intentional — Views are convenience aggregations, not direct copies.

If the View contains an unexpected profile, check `SourceProvider` and `SourceAuthSessionName` on the profile object to identify its origin:

```powershell
$plan.Request.Context.Views.Identity.Profile.SourceProvider
$plan.Request.Context.Views.Identity.Profile.SourceAuthSessionName
```

To get the profile from a specific provider, use the scoped source-of-truth path instead:

```powershell
$plan.Request.Context.Providers.Entra.Default.Identity.Profile
```

### Type conflict in context path

- A resolver cannot overwrite an existing path with incompatible type.
- Pre-existing context keys like `Providers` or `Views` must be hashtables.

### Invalid provider alias or AuthSessionName

- Provider alias and `AuthSessionName` must be valid path segments: `^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$`
- Dots (`.`) are not allowed as they are used as path separators.

### Inspecting resolved context data

When working with complex resolver outputs (entitlements, profiles), inspect the plan object directly after calling `New-IdlePlan`. This is the recommended approach during authoring and debugging. **Do not rely on template substitution for this purpose** — template substitution only resolves scalar values and cannot serialize whole objects or lists.

**Inspect the complete context tree:**

```powershell
$plan = New-IdlePlan -WorkflowPath ./workflow.psd1 -Request $req -Providers $providers

# Full context structure (use Depth 8 for deeply nested Views)
$plan.Request.Context | ConvertTo-Json -Depth 8

# Scoped source-of-truth namespace only
$plan.Request.Context.Providers | ConvertTo-Json -Depth 8

# Engine-defined Views only
$plan.Request.Context.Views | ConvertTo-Json -Depth 8
```

**Inspect a specific scoped path:**

```powershell
# Entitlements from one provider
$plan.Request.Context.Providers.Identity.Default.Identity.Entitlements | ConvertTo-Json -Depth 2

# Profile from one provider
$plan.Request.Context.Providers.Identity.Default.Identity.Profile | ConvertTo-Json -Depth 4

# Global merged View
$plan.Request.Context.Views.Identity.Entitlements | ConvertTo-Json -Depth 2
```

**Quick tabular view:**

```powershell
$plan.Request.Context.Views.Identity.Entitlements | Format-Table -AutoSize
```

**Inspect individual properties to understand the path structure:**

```powershell
# Check available properties on the profile object
$plan.Request.Context.Providers.Identity.Default.Identity.Profile | Get-Member

# Access profile attributes — attributes are nested under the Attributes key
$plan.Request.Context.Providers.Identity.Default.Identity.Profile.Attributes

# Check a specific attribute
$plan.Request.Context.Providers.Identity.Default.Identity.Profile.Attributes.DisplayName

# Check an entitlement entry and its source metadata
$plan.Request.Context.Views.Identity.Entitlements[0] | Get-Member
$plan.Request.Context.Views.Identity.Entitlements[0].Id
$plan.Request.Context.Views.Identity.Entitlements[0].SourceProvider
```

**Translating discovered structure to Condition paths:**

```powershell
# Profile attribute — path must include Attributes
Condition = @{
  Like = @{
    Path    = 'Request.Context.Providers.Identity.Default.Identity.Profile.Attributes.DisplayName'
    Pattern = '* (Contractor)'
  }
}

# Entitlement IDs — member-access enumeration extracts all Id values from the list
Condition = @{
  NotContains = @{
    Path  = 'Request.Context.Views.Identity.Entitlements.Id'
    Value = 'CN=BreakGlass-Users,OU=Groups,DC=example,DC=com'
  }
}
```

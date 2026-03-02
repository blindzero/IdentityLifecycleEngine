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

## Provider Selection and Authentication

### Provider Selection

Context Resolvers use providers to access external systems for reading identity and entitlement data.

**Auto-selection (recommended for single provider scenarios):**

If you have only one provider that advertises the capability, you can omit the `Provider` parameter:

```powershell
ContextResolvers = @(
    @{
        Capability = 'IdLE.Identity.Read'
        With = @{
            IdentityKey = '{{Request.IdentityKeys.EmployeeId}}'
            # Provider is omitted - IdLE auto-selects the matching provider
        }
    }
)
```

**Explicit provider selection (required for multiple providers):**

If you have multiple providers that advertise the same capability (e.g., multiple AD forests, AD + Entra ID), you must specify which provider to use:

```powershell
ContextResolvers = @(
    @{
        Capability = 'IdLE.Identity.Read'
        With = @{
            IdentityKey = '{{Request.IdentityKeys.EmployeeId}}'
            Provider    = 'PrimaryAD'  # explicit selection required
        }
    }
)
```

If multiple providers match and no explicit `Provider` is specified, planning fails with an ambiguity error.

### Authentication Sessions

Providers may require authentication to access external systems. IdLE uses **AuthSessionBroker** to manage authentication sessions.

**Basic usage (no authentication required):**

Some providers (like Mock) don't require authentication:

```powershell
ContextResolvers = @(
    @{
        Capability = 'IdLE.Identity.Read'
        With = @{
            IdentityKey = '{{Request.IdentityKeys.EmployeeId}}'
            Provider    = 'Mock'
        }
    }
)
```

**Using named auth sessions:**

For providers that require authentication, specify an `AuthSessionName` that references a session managed by your `AuthSessionBroker`:

```powershell
ContextResolvers = @(
    @{
        Capability = 'IdLE.Identity.Read'
        With = @{
            IdentityKey     = '{{Request.IdentityKeys.EmployeeId}}'
            Provider        = 'PrimaryAD'
            AuthSessionName = 'Tier0'  # Named session from AuthSessionBroker
        }
    }
)
```

The `AuthSessionBroker` must be configured in your `Providers` parameter when calling `New-IdlePlan`. The broker is responsible for:
- Managing credential/token lifecycle
- Acquiring and caching authentication sessions
- Providing sessions to providers and steps on demand

**Advanced: AuthSessionOptions**

Some `AuthSessionBroker` implementations accept additional options via `AuthSessionOptions`:

```powershell
ContextResolvers = @(
    @{
        Capability = 'IdLE.Identity.Read'
        With = @{
            IdentityKey         = '{{Request.IdentityKeys.EmployeeId}}'
            Provider            = 'EntraID'
            AuthSessionName     = 'GraphAPI'
            AuthSessionOptions  = @{
                Scopes = @('User.Read.All', 'Group.Read.All')
            }
        }
    }
)
```

> **Security note**: `AuthSessionOptions` must be data-only (hashtables, strings, numbers, booleans). ScriptBlocks and executable objects are rejected.

### Provider-Specific Identity Attributes

Different providers populate different attributes in the `Identity.Profile.Attributes` hashtable. After flattening, these become top-level properties.

**Active Directory (AD) provider** populates:
- `GivenName`, `Surname`, `DisplayName`
- `Department`, `Title`, `Description`
- `EmailAddress`, `UserPrincipalName`, `sAMAccountName`, `DistinguishedName`

**Entra ID (EntraID) provider** populates:
- `GivenName`, `Surname`, `DisplayName`
- `UserPrincipalName`, `Mail`
- `Department`, `JobTitle`, `OfficeLocation`, `CompanyName`

**Mock provider** populates:
- Any attributes you configure in your test/demo scenarios

For complete provider-specific attribute lists, see the individual provider documentation:
- [Active Directory Provider](../../reference/providers/provider-ad.md#capability-idleidentityread)
- [Entra ID Provider](../../reference/providers/provider-entraID.md#capability-idleidentityread)
- [Mock Provider](../../reference/providers/provider-mock.md#capability-idleidentityread)

---

## Identity Profile Attribute Flattening

When using `IdLE.Identity.Read`, the identity object returned by the provider contains an `Attributes` hashtable with properties like `DisplayName`, `EmailAddress`, `Department`, etc.

**IdLE automatically flattens these attributes** to the top level of `Request.Context.Identity.Profile` for convenient access in templates and conditions.

### Direct Access Pattern

You can access identity attributes directly at the top level:

```powershell
# ✅ Direct access
'{{Request.Context.Identity.Profile.DisplayName}}'
'{{Request.Context.Identity.Profile.EmailAddress}}'
'{{Request.Context.Identity.Profile.Department}}'
```

### Structure Example

After resolution, the profile object contains:

```powershell
Request.Context.Identity.Profile = @{
    PSTypeName   = 'IdLE.Identity'          # Preserved from provider
    IdentityKey  = 'user123'                # Core property
    Enabled      = $true                    # Core property
    DisplayName  = 'Jane Doe'               # Flattened from provider Attributes
    EmailAddress = 'jane.doe@example.com'   # Flattened from provider Attributes
    Department   = 'Engineering'            # Flattened from provider Attributes
    # ... all other attributes promoted to top level
}
```

### Reserved Property Names

The following core property names are **reserved** and will not be overwritten by attribute keys during flattening:

- `IdentityKey` - The identity key used by the workflow
- `Enabled` - The identity enabled status

The following is preserved as internal type metadata:

- `PSTypeName` - Type name metadata (e.g., 'IdLE.Identity')

If an attribute key conflicts with a reserved core property name, a verbose warning is emitted during planning, and the conflicting attribute is skipped:

```powershell
# Example: Provider returns Attributes = @{ IdentityKey = 'conflicting-value'; Enabled = $false }
# ⚠️  Verbose warnings emitted for both IdentityKey and Enabled
# ✅ Profile.IdentityKey returns the actual identity key (core property wins)
# ✅ Profile.Enabled returns the actual enabled status (core property wins)
# ❌ Conflicting attribute values are lost during flattening
```

---

## Multiple Resolvers and Precedence

### Execution Order

Context Resolvers are executed **sequentially in the order they are declared** in the workflow's `ContextResolvers` array:

```powershell
ContextResolvers = @(
    @{  # Executed first
        Capability = 'IdLE.Identity.Read'
        With = @{
            IdentityKey = '{{Request.IdentityKeys.EmployeeId}}'
            Provider    = 'PrimaryAD'
        }
    }
    @{  # Executed second
        Capability = 'IdLE.Entitlement.List'
        With = @{
            IdentityKey = '{{Request.IdentityKeys.EmployeeId}}'
            Provider    = 'PrimaryAD'
        }
    }
)
```

### Precedence for Overlapping Data

If multiple resolvers write to the **same context path**, later resolvers **overwrite** earlier ones:

```powershell
ContextResolvers = @(
    @{
        Capability = 'IdLE.Identity.Read'
        With = @{
            IdentityKey = '{{Request.IdentityKeys.EmployeeId}}'
            Provider    = 'PrimaryAD'      # Reads from Primary AD
        }
    }
    @{
        Capability = 'IdLE.Identity.Read'
        With = @{
            IdentityKey = '{{Request.IdentityKeys.EmployeeId}}'
            Provider    = 'EntraID'        # Overwrites Identity.Profile with Entra ID data
        }
    }
)
```

> **Important**: Both resolvers write to `Request.Context.Identity.Profile`. The **second resolver wins** and its data becomes the final `Identity.Profile` value.

### Using Multiple Providers with Different Auth Sessions

You can configure multiple resolvers that use different providers and authentication sessions for different systems:

```powershell
ContextResolvers = @(
    @{
        Capability      = 'IdLE.Identity.Read'
        With = @{
            IdentityKey     = '{{Request.IdentityKeys.sAMAccountName}}'
            Provider        = 'PrimaryAD'
            AuthSessionName = 'Tier0-AD'   # On-premises AD auth session
        }
    }
    @{
        Capability      = 'IdLE.Entitlement.List'
        With = @{
            IdentityKey     = '{{Request.IdentityKeys.UserPrincipalName}}'
            Provider        = 'EntraID'
            AuthSessionName = 'GraphAPI'   # Cloud auth session
        }
    }
)
```

Each resolver independently:
- Selects its own `Provider`
- Uses its own `AuthSessionName` (if authentication is required)
- Can pass provider-specific options via `AuthSessionOptions`

### Avoiding Conflicts

To avoid unintended overwrites when using multiple providers:

1. **Use different capabilities** that write to different context paths:
   - `IdLE.Identity.Read` → `Request.Context.Identity.Profile`
   - `IdLE.Entitlement.List` → `Request.Context.Identity.Entitlements`

2. **Declare resolvers in intentional order** if you need the later resolver to win:
   ```powershell
   # Get basic profile from AD first
   @{ Capability = 'IdLE.Identity.Read'; With = @{ Provider = 'AD' } }
   
   # Overwrite with cloud-enriched profile if needed
   @{ Capability = 'IdLE.Identity.Read'; With = @{ Provider = 'EntraID' } }
   ```

3. **Use unique identity keys** appropriate for each provider:
   - AD providers often use `sAMAccountName` or `DistinguishedName`
   - Entra ID providers use `UserPrincipalName` or `ObjectId`

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

### Inspecting resolved context data

When working with complex objects (like entitlements), you may need to inspect the structure to determine the correct path syntax for Conditions or to understand what properties are available.

**Method 1: Inspect the plan object after planning**

```powershell
$plan = New-IdlePlan -WorkflowPath ./workflow.psd1 -Request $req -Providers $providers

# View the entire context structure
$plan.Request.Context | ConvertTo-Json -Depth 5

# View specific resolved data
$plan.Request.Context.Identity.Entitlements | ConvertTo-Json -Depth 2
```

**Method 2: Use Format-Table for quick inspection**

```powershell
# After planning, inspect entitlements structure
$plan.Request.Context.Identity.Entitlements | Format-Table -AutoSize
```

**Method 3: Access individual properties**

```powershell
# Check if entitlements are objects with properties
$plan.Request.Context.Identity.Entitlements[0] | Get-Member
$plan.Request.Context.Identity.Entitlements[0].Id
$plan.Request.Context.Identity.Entitlements[0].DisplayName
```

**Using discovered structure in Conditions**

Once you know the structure (e.g., entitlements are objects with `Kind`, `Id`, `DisplayName`), use member-access enumeration in your condition paths:

```powershell
# Extract Id values from all entitlement objects
Condition = @{
  NotContains = @{
    Path  = 'Request.Context.Identity.Entitlements.Id'
    Value = 'CN=BreakGlass-Users,OU=Groups,DC=example,DC=com'
  }
}
```

See [Conditions - Member-Access Enumeration](./conditions.md#member-access-enumeration) for details.

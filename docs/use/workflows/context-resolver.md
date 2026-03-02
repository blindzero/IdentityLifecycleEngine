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

## Complete Example with Inline Comments

```powershell
@{
  Name           = 'Offboarding - Context Resolver Example'
  LifecycleEvent = 'Leaver'

  # ContextResolvers populate Request.Context.* during planning
  # They execute sequentially in declaration order BEFORE step conditions are evaluated
  ContextResolvers = @(
    
    # Resolver 1: Read identity profile from Active Directory
    @{
      Capability = 'IdLE.Identity.Read'           # REQUIRED - Must be from allow-list
      With = @{
        IdentityKey     = '{{Request.IdentityKeys.EmployeeId}}'  # REQUIRED - Template substitution supported
        Provider        = 'PrimaryAD'                             # OPTIONAL - Auto-selected if only one provider matches
        AuthSessionName = 'Tier0-AD'                             # OPTIONAL - Named auth session from AuthSessionBroker
        # AuthSessionOptions = @{ Scopes = @('...') }           # OPTIONAL - Provider-specific auth options (must be data-only)
      }
      # Output: Request.Context.Identity.Profile (fixed path, cannot be changed)
      # After flattening: Profile.DisplayName, Profile.EmailAddress, etc. are accessible directly
    }

    # Resolver 2: List entitlements for the identity
    @{
      Capability = 'IdLE.Entitlement.List'
      With = @{
        IdentityKey = '{{Request.IdentityKeys.EmployeeId}}'
        Provider    = 'PrimaryAD'      # OPTIONAL
        # AuthSessionName can be different per resolver if needed
      }
      # Output: Request.Context.Identity.Entitlements (fixed path)
    }
  )

  Steps = @(
    # Step conditions can reference resolved context data
    @{
      Name = 'Disable account only if identity exists in AD'
      Type = 'IdLE.Step.DisableIdentity'
      Condition = @{
        Exists = 'Request.Context.Identity.Profile'  # Check if identity was found
      }
    }

    # Template substitution can use flattened attributes
    @{
      Name = 'Send notification email'
      Type = 'IdLE.Step.EmitEvent'
      With = @{
        # Direct access to flattened attributes (no .Attributes. needed)
        Message = 'Disabled account for {{Request.Context.Identity.Profile.DisplayName}} ({{Request.Context.Identity.Profile.EmailAddress}})'
      }
    }

    # Preconditions can also reference context (evaluated at execution time)
    @{
      Name = 'Revoke admin entitlements'
      Type = 'IdLE.Step.PruneEntitlements'
      Precondition = @{
        Exists = 'Request.Context.Identity.Entitlements'  # Ensure entitlements were resolved
      }
    }
  )
}
```

### Resolver Configuration Keys

| Key | Type | Required | Description |
|-----|------|----------|-------------|
| `Capability` | `string` | **Yes** | Read-only capability from allow-list: `IdLE.Identity.Read`, `IdLE.Entitlement.List` |
| `With` | `hashtable` | **Yes**¹ | Inputs required by the capability. Template substitution supported. |
| `With.IdentityKey` | `string` | **Yes** | Identity key for lookup. Required by both capabilities. |
| `With.Provider` | `string` | No | Provider alias. Auto-selected if omitted and only one provider matches. Required if multiple providers advertise the capability. |
| `With.AuthSessionName` | `string` | No | Named auth session to acquire via `AuthSessionBroker`. |
| `With.AuthSessionOptions` | `hashtable` | No | Provider-specific auth options. Must be data-only (no ScriptBlocks). |

¹ Technically optional, but required in practice for all current capabilities.

### Output Paths (Predefined)

Each capability writes to a fixed path under `Request.Context`:

| Capability | Output Path | Description |
|------------|-------------|-------------|
| `IdLE.Identity.Read` | `Identity.Profile` | Identity object with attributes flattened to top level |
| `IdLE.Entitlement.List` | `Identity.Entitlements` | Array of entitlement objects |

> **Important**: Output paths cannot be customized. If multiple resolvers use the same capability, later resolvers overwrite earlier ones (last-writer-wins).

---

## Provider Selection and Authentication

### Provider Selection

**Auto-selection:** If only one provider advertises the capability, omit `Provider`:

```powershell
With = @{
    IdentityKey = '{{Request.IdentityKeys.EmployeeId}}'
    # Provider omitted - auto-selected
}
```

**Explicit selection:** Required when multiple providers match:

```powershell
With = @{
    IdentityKey = '{{Request.IdentityKeys.EmployeeId}}'
    Provider    = 'PrimaryAD'  # Disambiguates between PrimaryAD and EntraID
}
```

### Authentication

Some providers require authentication via `AuthSessionBroker`:

```powershell
With = @{
    IdentityKey     = '{{Request.IdentityKeys.EmployeeId}}'
    Provider        = 'PrimaryAD'
    AuthSessionName = 'Tier0'  # Named session from AuthSessionBroker
}
```

Advanced auth options (provider-specific):

```powershell
AuthSessionOptions = @{
    Scopes = @('User.Read.All', 'Group.Read.All')
}
```

> **Security**: `AuthSessionOptions` must be data-only (no ScriptBlocks).

### Provider-Specific Attributes

Different providers populate different attributes. After flattening, attributes become top-level properties:

- **AD**: `GivenName`, `Surname`, `DisplayName`, `Department`, `Title`, `EmailAddress`, `UserPrincipalName`, `sAMAccountName`, `DistinguishedName`
- **Entra ID**: `GivenName`, `Surname`, `DisplayName`, `UserPrincipalName`, `Mail`, `Department`, `JobTitle`, `OfficeLocation`
- **Mock**: Configurable test attributes

See provider docs for complete lists: [AD](../../reference/providers/provider-ad.md#capability-idleidentityread), [Entra ID](../../reference/providers/provider-entraID.md#capability-idleidentityread), [Mock](../../reference/providers/provider-mock.md#capability-idleidentityread)

---

## Identity Profile Attribute Flattening

Provider identity objects contain an `Attributes` hashtable. **IdLE automatically flattens these to top-level properties** for direct access:

```powershell
# ✅ Direct access (attributes flattened to top level)
'{{Request.Context.Identity.Profile.DisplayName}}'
'{{Request.Context.Identity.Profile.EmailAddress}}'

# ❌ Nested access no longer supported (Attributes removed after flattening)
'{{Request.Context.Identity.Profile.Attributes.DisplayName}}'
```

**Flattened structure:**

```powershell
Request.Context.Identity.Profile = @{
    PSTypeName   = 'IdLE.Identity'  # Preserved from provider
    IdentityKey  = 'user123'        # Core property
    Enabled      = $true            # Core property
    DisplayName  = 'Jane Doe'       # Flattened from Attributes
    EmailAddress = 'jane@example.com'  # Flattened from Attributes
    # ... other attributes as top-level properties
}
```

**Reserved names:** `IdentityKey` and `Enabled` cannot be overwritten by attributes. Conflicts trigger verbose warnings and the attribute is skipped.

---

## Multiple Resolvers and Precedence

Resolvers execute **sequentially in declaration order**. If multiple resolvers write to the same path, **later ones overwrite earlier ones** (last-writer-wins):

```powershell
ContextResolvers = @(
    @{ Capability = 'IdLE.Identity.Read'; With = @{ Provider = 'PrimaryAD' } }    # Executes first
    @{ Capability = 'IdLE.Identity.Read'; With = @{ Provider = 'EntraID' } }      # Overwrites Profile with EntraID data
)
# Result: Request.Context.Identity.Profile contains EntraID data only
```

**Using different providers per resolver:**

```powershell
ContextResolvers = @(
    @{
        Capability = 'IdLE.Identity.Read'
        With = @{
            IdentityKey     = '{{Request.IdentityKeys.sAMAccountName}}'
            Provider        = 'PrimaryAD'
            AuthSessionName = 'Tier0-AD'    # On-premises AD auth
        }
    }
    @{
        Capability = 'IdLE.Entitlement.List'
        With = @{
            IdentityKey     = '{{Request.IdentityKeys.UserPrincipalName}}'
            Provider        = 'EntraID'
            AuthSessionName = 'GraphAPI'     # Cloud auth (different session)
        }
    }
)
# Result: Profile from AD, Entitlements from EntraID (no conflicts - different paths)
```

**Best practices:**
- Use different capabilities to avoid overwrites (`IdLE.Identity.Read` → `Identity.Profile`, `IdLE.Entitlement.List` → `Identity.Entitlements`)
- If intentional overwrite is needed, declare resolvers in the desired order
- Use appropriate identity keys for each provider (AD: `sAMAccountName`, Entra ID: `UserPrincipalName`)

---

## Common Patterns and Troubleshooting

### Resolve Once, Use Everywhere

Resolve identity/entitlements once during planning, then reuse in conditions, preconditions, and templates:

```powershell
# In step condition
Condition = @{ Exists = 'Request.Context.Identity.Profile' }

# In template
Message = '{{Request.Context.Identity.Profile.DisplayName}} offboarded'
```

### Guard Destructive Operations

Only perform actions if identity exists:

```powershell
Condition = @{ Exists = 'Request.Context.Identity.Profile' }
```

### Troubleshooting

| Problem | Solution |
|---------|----------|
| Resolver not executed | Ensure `ContextResolvers` is at workflow root level |
| Capability not permitted | Only `IdLE.Identity.Read` and `IdLE.Entitlement.List` are allowed |
| Ambiguous provider | Specify `With.Provider` explicitly when multiple providers match |
| Context value missing | Verify `With` parameters and template placeholders resolve correctly |
| Type conflict in context | Cannot overwrite existing context path with incompatible type |

### Inspecting Resolved Context

View resolved context after planning:

```powershell
$plan = New-IdlePlan -WorkflowPath ./workflow.psd1 -Request $req -Providers $providers

# View entire context
$plan.Request.Context | ConvertTo-Json -Depth 5

# View specific data
$plan.Request.Context.Identity.Profile
$plan.Request.Context.Identity.Entitlements | Format-Table

# Inspect object structure
$plan.Request.Context.Identity.Entitlements[0] | Get-Member
```

Use discovered structure in conditions:

```powershell
Condition = @{
  NotContains = @{
    Path  = 'Request.Context.Identity.Entitlements.Id'  # Member-access enumeration
    Value = 'CN=BreakGlass-Users,OU=Groups,DC=example,DC=com'
  }
}
```

See [Conditions - Member-Access Enumeration](./conditions.md#member-access-enumeration) for details.

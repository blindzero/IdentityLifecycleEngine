---
title: Capabilities
description: Reference for IdLE capability identifiers and naming rules.
---

This document defines the **IdLE capability catalog** and the rules for capability IDs.
Capabilities are the contract between **Steps**, **Providers**, and the **Planning Engine**.

> Note: IdLE is still pre-1.0. Capability IDs may evolve. This document should be treated as the source of truth for IDs once stabilized.

For the conceptual model (why capabilities exist, how discovery/merging works, and how validation behaves), see
- [About -> Concepts](../about/concepts.md)
- [Extend -> Extensibility](../extend/extensibility.md)
- [Extend -> Providers](../extend/providers.md)

---

## Naming rules

A capability is a **stable string identifier** describing a feature a provider can perform.

Rules:

- Must start with the `IdLE.` prefix.
- Use **PascalCase** for each segment (e.g., `Identity`, `OutOfOffice`).
- Use **verbs** for the last segment whenever possible (`Read`, `List`, `Create`, `Disable`, `Ensure`).
- No provider names inside a capability ID. Capabilities describe *what* is possible, not *where* it is implemented.
- Dot-separated segments (for example: `IdLE.Identity.Read`)
- No whitespace
- Starts with a letter
- Keep identifiers stable (treat changes as breaking changes)

Examples:

- `IdLE.Identity.Read`
- `IdLE.Identity.Disable`
- `IdLE.Entitlement.List`

---

## Catalog

The catalog below lists capabilities currently referenced by the documentation and expected by steps/providers.

### Identity

#### `IdLE.Identity.Read`
Read a single identity record by a stable identifier (e.g., object id, SID, GUID). Used to confirm existence and fetch current state before planning or executing changes.

#### `IdLE.Identity.List`
List/search identities based on a query/filter (e.g., by UPN, employeeId, mail, or custom criteria). Used for lookup/discovery scenarios.

#### `IdLE.Identity.Create`
Create a new identity/account object in the target system.

#### `IdLE.Identity.Enable`
Enable/reactivate an identity/account that exists but is disabled (e.g., unlock, enable user, re-enable sign-in).

#### `IdLE.Identity.Disable`
Disable/suspend an identity/account (soft-deprovision). Should be idempotent (disabling an already disabled identity is a no-op).

#### `IdLE.Identity.Move`
Move/relocate an identity within the same system boundary (e.g., change OU, move to another container, transfer to another org unit).

#### `IdLE.Identity.Delete`
Delete an identity/account (hard deprovision). Typically irreversible; steps should be careful and may require explicit confirmation patterns.

#### `IdLE.Identity.Attribute.Ensure`
Ensure one or more attributes on an identity match desired state (set/clear/replace). Provider decides how to map logical attribute names to system fields.

### Entitlements

#### `IdLE.Entitlement.List`
List entitlements/assignments for an identity and/or enumerate available entitlements (licenses, groups, roles).

#### `IdLE.Entitlement.Grant`
Grant/assign an entitlement to an identity (e.g., add group membership, assign license/role). Must be idempotent.

#### `IdLE.Entitlement.Revoke`
Revoke/remove an entitlement from an identity. Must be idempotent.

#### `IdLE.Entitlement.Prune`
Explicit opt-in for bulk entitlement convergence ("remove all except"). Providers that advertise this capability support the `IdLE.Step.PruneEntitlements` step, which removes all entitlements of a given kind except an explicit keep-set and/or pattern-matched entitlements. This is a separate capability from `Revoke` because the operation is bulk and destructive by design. Providers must also implement `ListEntitlements` and `RevokeEntitlement` (and optionally `GrantEntitlement`) to support this step.

### Mailbox

#### `IdLE.Mailbox.Info.Read`
Read mailbox metadata (existence, type, primary addresses, key properties) without reading message contents.

#### `IdLE.Mailbox.Type.Ensure`
Ensure mailbox type/config matches desired state (e.g., shared vs user mailbox, litigation hold mode where applicable).

#### `IdLE.Mailbox.OutOfOffice.Ensure`
Ensure out-of-office / automatic replies configuration matches desired state.


> Compatibility note: older docs or experiments may reference `IdLE.Mailbox.Read`. Prefer `IdLE.Mailbox.Info.Read` for metadata-only access, to avoid ambiguity with reading message contents.

### Directory synchronization

#### `IdLE.DirectorySync.Status`
Read directory synchronization status/health (e.g., scheduler state, last run, errors) for a directory sync provider.

#### `IdLE.DirectorySync.Trigger`
Trigger a directory synchronization run (e.g., delta sync). Provider may expose safeguards/retry behavior.

---

## Relationship to steps

Steps require capabilities, but **capabilities are not step names**.

Examples of step type identifiers (not capabilities):

- `IdLE.Step.EnsureAttributes`
- `IdLE.Step.DisableIdentity`

If you need a mapping between step types and required capabilities, document that mapping next to the
step implementation and/or in the step reference.

---

## Provider declarations

Providers should declare the capabilities they implement. During planning, IdLE validates that all planned steps can be satisfied by the selected provider set (including any host-supplied capabilities).

Recommended provider documentation pattern:

- List supported capabilities in the provider documentation.
- If a capability is only partially supported (e.g., limited attribute set), document constraints explicitly.


---

## ContextResolvers: read-only capabilities and Context namespace

Workflows may declare a `ContextResolvers` section to populate `Request.Context.*` at planning time using read-only provider capabilities. Only the capabilities listed below are permitted in `ContextResolvers`.

Each resolver writes to a **provider/auth-scoped source-of-truth path** under `Request.Context.Providers.*` and engine-defined **Views** for capabilities with aggregation semantics. The paths are not user-configurable.

### Source-of-truth paths

```
Request.Context.Providers.<ProviderAlias>.<AuthSessionKey>.<CapabilitySubPath>
```

| Capability | CapabilitySubPath | Required `With` keys |
|---|---|---|
| `IdLE.Entitlement.List` | `Identity.Entitlements` | `IdentityKey` (string) |
| `IdLE.Identity.Read` | `Identity.Profile` | `IdentityKey` (string) |

Where `<AuthSessionKey>` is `Default` when `With.AuthSessionName` is not specified.

Examples:
- `Request.Context.Providers.Entra.Default.Identity.Entitlements`
- `Request.Context.Providers.AD.CorpAdmin.Identity.Entitlements`
- `Request.Context.Providers.Identity.Default.Identity.Profile`

### Views (engine-defined aggregations)

For `IdLE.Entitlement.List`, the engine additionally builds (list merge — all entries preserved):

| View | Path |
|---|---|
| All providers, all sessions | `Request.Context.Views.Identity.Entitlements` |
| One provider, all sessions | `Request.Context.Views.Providers.<ProviderAlias>.Identity.Entitlements` |
| All providers, one session | `Request.Context.Views.Sessions.<AuthSessionKey>.Identity.Entitlements` |
| One provider, one session | `Request.Context.Views.Providers.<ProviderAlias>.Sessions.<AuthSessionKey>.Identity.Entitlements` |

> **Note**: `IdLE.Entitlement.List` writes an array of entitlement objects. Each entry includes:
> `Kind` (string), `Id` (string), and optionally `DisplayName` (string),
> plus source metadata: `SourceProvider` (string) and `SourceAuthSessionName` (string).
> To reference entitlement Ids in Conditions, use the `.Id` member-access pattern.
> See [Conditions - Member-Access Enumeration](../use/workflows/conditions.md#member-access-enumeration).

For `IdLE.Identity.Read`, the engine additionally builds (single object — last writer wins, sorted by provider alias asc then auth key asc):

| View | Path |
|---|---|
| All providers, all sessions | `Request.Context.Views.Identity.Profile` |
| One provider, all sessions | `Request.Context.Views.Providers.<ProviderAlias>.Identity.Profile` |
| All providers, one session | `Request.Context.Views.Sessions.<AuthSessionKey>.Identity.Profile` |
| One provider, one session | `Request.Context.Views.Providers.<ProviderAlias>.Sessions.<AuthSessionKey>.Identity.Profile` |

> **Note**: `IdLE.Identity.Read` writes a single profile object, annotated with `SourceProvider` and `SourceAuthSessionName`.
> When multiple providers or sessions contribute to a view scope, the profile from the last entry
> in sort order (provider alias ascending, then auth key ascending) is used.

> **Note**: `IdLE.Identity.Read` automatically flattens identity attributes to the top level of `Request.Context.Identity.Profile`. You can access attributes directly (e.g., `Request.Context.Identity.Profile.DisplayName`) instead of via the nested path (e.g., `Request.Context.Identity.Profile.Attributes.DisplayName`). The `Attributes` hashtable is preserved for backwards compatibility. See [Context Resolvers - Identity Profile Attribute Flattening](../use/workflows/context-resolver.md#identity-profile-attribute-flattening) for details.

### Example

```powershell
ContextResolvers = @(
    @{
        Capability = 'IdLE.Entitlement.List'
        With       = @{
            IdentityKey = '{{Request.IdentityKeys.EmployeeId}}'
            Provider    = 'Identity'   # optional; auto-selected if omitted
        }
        # Writes to: Request.Context.Providers.Identity.Default.Identity.Entitlements
        # View:      Request.Context.Views.Identity.Entitlements
    }
    @{
        Capability = 'IdLE.Identity.Read'
        With       = @{ IdentityKey = '{{Request.IdentityKeys.EmployeeId}}' }
        # Writes to: Request.Context.Providers.Identity.Default.Identity.Profile
    }
)
```

Steps can then reference the resolved data in their `Condition` using the global view (most common) or scoped paths:

```powershell
# Global view: check if entitlements exist from any provider
Condition = @{ Exists = 'Request.Context.Views.Identity.Entitlements' }

# Global view: check if a specific group Id is present across all providers
Condition = @{
  Contains = @{
    Path  = 'Request.Context.Views.Identity.Entitlements.Id'
    Value = 'CN=Admins,OU=Groups,DC=example,DC=com'
  }
}

# Scoped path: check entitlements from a specific provider only
Condition = @{ Exists = 'Request.Context.Providers.Identity.Default.Identity.Entitlements' }
```

> **Tip**: Use `$plan.Request.Context.Views.Identity.Entitlements | Format-Table` to inspect resolved entitlements. See [Context Resolvers - Inspecting resolved context data](../use/workflows/context-resolver.md#inspecting-resolved-context-data).

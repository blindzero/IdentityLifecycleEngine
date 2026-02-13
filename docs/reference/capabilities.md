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

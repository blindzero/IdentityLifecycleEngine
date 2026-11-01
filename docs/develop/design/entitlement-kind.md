---
title: "Design: Entitlement Kind"
sidebar_label: "Design: Entitlement Kind"
---

# Design: Entitlement Kind

| | |
| --- | --- |
| **Status** | Proposed |
| **Issue** | [#289](https://github.com/blindzero/IdentityLifecycleEngine/issues/289) |
| **Target** | v1.0.0 |
| **Affects** | `IdLE.Step.PruneEntitlements`, `IdLE.Step.PruneEntitlementsEnsureKeep`, entitlement provider contract (`ListEntitlements`, `ResolveEntitlement`, Kind validation), AD / Entra ID providers, context resolver `IdLE.Entitlement.List` |
| **Unchanged** | `IdLE.Step.EnsureEntitlement` schema (`With.Entitlement.Kind`), Mock provider Kind handling, Host API |
| **Compatibility** | Breaking, no compatibility layer (as #324) |

## Problem

An entitlement is identified by `Kind` + `Id`. Today `Kind` is handled inconsistently:

- `PruneEntitlements*` require `With.Kind` (the prune scope) and accept an optional `Keep[].Kind`, which repeats the
  scope (`Kind = 'Group'` plus `Keep = @(@{ Kind = 'Group'; Id = ... })`). A Keep entry with a different Kind is
  resolved with the scope Kind, matched by `Id` only, and granted with its own Kind by `PruneEntitlementsEnsureKeep`.
- `ResolveEntitlement(Kind, Entitlement)` carries a second Kind that providers ignore.
- Providers do not reject Kinds they do not support. The AD provider treats every Kind as a group
  (`Kind = 'AdministrativeUnit'; Id = 'Sales'` adds the user to a group named `Sales`) and a prune with a foreign Kind
  silently removes nothing. A misspelled Kind (`'Groups'`) behaves the same way on Entra ID.
- The context resolver `IdLE.Entitlement.List` lists all Kinds. On Entra ID it always reads Administrative Units, so
  group-only workflows need `AdministrativeUnit.Read.All`.

## Principle

`Kind` belongs to the entitlement reference. A step-level Kind exists only where it defines a **scope** (what a prune
may remove, what a resolver lists). Providers own the set of Kinds they support and reject everything else before
changing anything.

## 1. EnsureEntitlement

No change: `With.Entitlement = @{ Kind; Id; DisplayName }`, one entitlement per step. Multiple entitlements per step
are out of scope.

## 2. PruneEntitlements / PruneEntitlementsEnsureKeep

- `With.Kind` stays required: the explicit scope of what may be removed.
- `Keep[].Kind` is optional. When set it must equal `With.Kind` (case-insensitive); otherwise the step fails before
  listing or changing anything:
  `PruneEntitlements: Keep entry 'X' has Kind 'AdministrativeUnit', but the step prunes Kind 'Group'.`
- Keep entries are resolved and granted with `With.Kind`.
- Examples omit the redundant `Keep[].Kind`.

Mixed Kinds in one prune are not supported; use one step per Kind.

## 3. Provider contract

| Method | Contract |
| --- | --- |
| `ListEntitlements(IdentityKey[, AuthSession][, Kind])` | Optional `Kind` filters the result. An unsupported `Kind` throws. |
| `GrantEntitlement(IdentityKey, Entitlement[, AuthSession])` | Throws for an unsupported `Entitlement.Kind`. |
| `RevokeEntitlement(IdentityKey, Entitlement[, AuthSession])` | Throws for an unsupported `Entitlement.Kind`. |
| `ResolveEntitlement(Entitlement[, AuthSession])` (optional) | **Changed:** no `Kind` parameter; uses `Entitlement.Kind`. |
| `BulkGrantEntitlements` / `BulkRevokeEntitlements` (optional) | Unsupported Kinds throw (not reported per item). |

- Kind comparison is case-insensitive; providers return the canonical casing.
- Unsupported Kind error: `Entitlement Kind 'AdministrativeUnit' is not supported by this provider. Supported Kinds: Group.`
- Because both prune steps call `ListEntitlements(Kind)` first, an unsupported scope fails before any revoke.

| Provider | Supported Kinds |
| --- | --- |
| AD | `Group` (new: `ListEntitlements` accepts `Kind`) |
| Entra ID | `Group`, `AdministrativeUnit` (the unreachable "missing Kind defaults to Group" branches are removed) |
| Mock | any non-empty Kind (test provider) |

Plan-time Kind validation (providers declaring their Kinds) is deferred to after v1.0; it can be added as an optional
provider method without breaking this contract.

## 4. Context resolver `IdLE.Entitlement.List`

- New optional `With.Kind` (non-empty string). The engine passes it to `ListEntitlements` when the method declares
  `Kind`, and always filters the result by Kind, so providers without the parameter behave the same.
- Without `With.Kind` the behavior is unchanged (all Kinds).
- **Default (proposed):** two resolvers with the same capability, provider and auth session fail with an error instead
  of silently overwriting each other's `Request.Context.Providers.<Alias>.<Session>.*` result. To list several Kinds
  of one provider, omit `With.Kind` and filter in the Condition.

## 5. Migration

| Before | After |
| --- | --- |
| `Keep = @(@{ Kind = 'Group'; Id = 'g1' })` with `Kind = 'Group'` | `Keep = @(@{ Id = 'g1' })` (the old form stays valid) |
| `Keep[].Kind` different from `With.Kind` | Error; use one prune step per Kind. |
| Provider `ResolveEntitlement($Kind, $Entitlement, $AuthSession)` | `ResolveEntitlement($Entitlement, $AuthSession)` |
| AD entitlement step with a non-`Group` Kind | Error (was: treated as a group). |
| Entra ID group-only resolver needed `AdministrativeUnit.Read.All` | Add `With.Kind = 'Group'`. |

## 6. Tests

- Prune: Keep entry without Kind uses the scope; mismatching Keep Kind fails before any provider call that changes
  state (regression); `ResolveEntitlement` receives only the entitlement.
- AD / Entra ID: unsupported Kind throws in List/Grant/Revoke/Resolve (and Bulk for Entra ID); canonical casing.
- Resolver: `With.Kind` passed through and filtered (provider with and without `Kind`); duplicate resolver fails.
- Entitlement provider contract tests: ResolveEntitlement signature when implemented.

## Documentation

Folded into `docs/extend/providers.md` (entitlement provider contract), the step help (generated step reference),
`docs/use/workflows/context-resolver.md`, `docs/reference/capabilities.md` and the provider references; this design
document is then removed.

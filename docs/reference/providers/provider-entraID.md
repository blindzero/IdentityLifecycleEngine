---
title: Provider Reference - Microsoft Entra ID (IdLE.Provider.EntraID)
sidebar_label: Entra ID
---

import CodeBlock from '@theme/CodeBlock';

import EntraJoiner from '@site/../examples/workflows/templates/entraid-joiner.psd1';
import EntraLeaver from '@site/../examples/workflows/templates/entraid-leaver.psd1';

## Summary

- **Module:** `IdLE.Provider.EntraID`
- **What it’s for:** Entra ID user lifecycle + group and Administrative Unit entitlements (Microsoft Graph API)
- **Targets:** Microsoft Entra ID (formerly Azure AD) via Microsoft Graph (v1.0)

## When to use

Use this provider when your workflow needs to manage **Entra ID user accounts**, for example:

- **Joiner:** create or update a user, set baseline attributes, assign baseline groups and Administrative Units
- **Mover:** update org attributes and managed groups (covered as *optional patterns* inside the Joiner template)
- **Leaver:** disable account, revoke sessions, optional cleanup (groups, Administrative Units, delete)

Non-goals:

- Obtaining tokens or storing secrets (handled by your runtime + AuthSessionBroker pattern)
- Exchange Online mailbox configuration (use the Exchange Online provider/steps)

## Getting started

### Requirements

- Your runtime must be able to supply a **Microsoft Graph auth session** (token/session object) to IdLE
- Graph permissions must allow the actions you intend to run (users, groups, Administrative Units)

### Install (PowerShell Gallery)

```powershell
Install-Module IdLE.Provider.EntraID -Scope CurrentUser
```

### Import

```powershell
Import-Module IdLE.Provider.EntraID
```

## Quickstart

Create provider (safe defaults):

```powershell
$provider = New-IdleEntraIDIdentityProvider
```

Typical alias pattern:

```powershell
$providers = @{
  Identity = $provider
}
```

In a workflow template, reference your auth session via steps (example):

```powershell
With = @{
  AuthSessionName    = 'MicrosoftGraph'
  AuthSessionOptions = @{ Role = 'Admin' }
}
```

> Keep tokens/secrets **out of workflow files**. Resolve them in the host/runtime and provide them via the broker.

## Authentication

This provider expects Graph authentication to be supplied at runtime (AuthSessionBroker pattern). Common session shapes used by hosts include:

- raw access token string (Bearer token)
- object with an `AccessToken` property
- object that can produce a token (e.g., `GetAccessToken()`)

Recommended wiring in examples:
- `AuthSessionName = 'MicrosoftGraph'`
- `AuthSessionOptions = @{ Role = 'Admin' }` for routing (optional)
- Use a more privileged role only for privileged actions (e.g. delete)

## Context Resolvers

This provider supports Context Resolvers for the allowlisted, read-only capabilities below.

### Capability: `IdLE.Identity.Read`

Writes to scoped path: `Request.Context.Providers.<ProviderAlias>.<AuthSessionKey>.Identity.Profile`  
Engine-defined View: `Request.Context.Views.Identity.Profile`  
Type: `PSCustomObject` (`PSTypeName = 'IdLE.Identity'`)

Top-level properties:

| Property | Type | Notes |
| --- | --- | --- |
| `PSTypeName` | `string` | Always `IdLE.Identity`. |
| `IdentityKey` | `string` | The identity key used by the workflow (typically the Entra user `id`). |
| `Enabled` | `bool` | Derived from Entra user `accountEnabled`. |
| `Attributes` | `hashtable` | Key/value bag; keys are strings; values are typically `string`. |

`Attributes` keys populated by this provider (when present on the user object):

| Attribute key | Type | Source (Graph field) |
| --- | --- | --- |
| `GivenName` | `string` | `givenName` |
| `Surname` | `string` | `surname` |
| `DisplayName` | `string` | `displayName` |
| `UserPrincipalName` | `string` | `userPrincipalName` |
| `Mail` | `string` | `mail` |
| `Department` | `string` | `department` |
| `JobTitle` | `string` | `jobTitle` |
| `OfficeLocation` | `string` | `officeLocation` |
| `CompanyName` | `string` | `companyName` |

> **Attribute access**: Profile attributes are nested under the `Attributes` key. In Conditions, use `Request.Context.Views.Identity.Profile.Attributes.DisplayName` (or the scoped `Request.Context.Providers.<ProviderAlias>.<AuthSessionKey>.Identity.Profile.Attributes.DisplayName`), **not** `Request.Context.Views.Identity.Profile.DisplayName` (or `Request.Context.Providers.<ProviderAlias>.<AuthSessionKey>.Identity.Profile.DisplayName`).

### Capability: `IdLE.Entitlement.List`

Writes to scoped path: `Request.Context.Providers.<ProviderAlias>.<AuthSessionKey>.Identity.Entitlements`  
Engine-defined View: `Request.Context.Views.Identity.Entitlements`  
Type: `object[]` (array of `PSCustomObject`, `PSTypeName = 'IdLE.Entitlement'`)

Each element represents one entitlement (group membership or Administrative Unit membership):

**Group entitlements (`Kind = 'Group'`):**

| Property | Type | Notes |
| --- | --- | --- |
| `PSTypeName` | `string` | Always `IdLE.Entitlement`. |
| `Kind` | `string` | Always `Group`. |
| `Id` | `string` | Entra group object ID (GUID). |
| `Mail` | `string` or `$null` | Group `mail` (if returned by Graph). |

**Administrative Unit entitlements (`Kind = 'AdministrativeUnit'`):**

| Property | Type | Notes |
| --- | --- | --- |
| `PSTypeName` | `string` | Always `IdLE.Entitlement`. |
| `Kind` | `string` | Always `AdministrativeUnit`. |
| `Id` | `string` | Entra Administrative Unit object ID (GUID). |

Notes:
- The output paths are fixed by the engine and cannot be changed.
- Each entry is automatically annotated with `SourceProvider` and `SourceAuthSessionName` metadata.
- Use the global View (`Request.Context.Views.Identity.Entitlements`) in **Conditions** when you don't need to filter by provider. Use the scoped path when you need results from a specific provider only.
- See [Context Resolvers](../../use/workflows/context-resolver.md) for the full path reference.

## Administrative Unit entitlements

Administrative Units (AUs) are modelled as `Kind = 'AdministrativeUnit'` entitlements. They control which scoped admins can manage which users — assigning a user to an AU makes them visible to that AU's scoped admin roles.

### Supported operations

| Operation | Behaviour |
| --- | --- |
| `ListEntitlements` | Returns all current AU memberships alongside group memberships. |
| `GrantEntitlement` | Adds the user to the specified AU. Idempotent — no error if already a member. |
| `RevokeEntitlement` | Removes the user from the specified AU. Idempotent — no error if not a member. |
| `PruneEntitlements` | Covered automatically: `ListEntitlements` returns both groups and AUs, so the Prune step removes unlisted AUs in the same pass as groups. |

### Workflow usage

```powershell
# Ensure a user is assigned to an Administrative Unit (Joiner / Mover)
@{
    Name = 'Assign to HR Administrative Unit'
    Type = 'IdLE.Step.EnsureEntitlement'
    With = @{
        IdentityKey     = '{{Request.IdentityKeys.Id}}'
        Provider        = 'Entra'
        AuthSessionName = 'MicrosoftGraph'
        Entitlement     = @{ Kind = 'AdministrativeUnit'; Id = '<AU-ObjectId-GUID>' }
        State           = 'Present'
    }
}

# Remove a user from an Administrative Unit (Leaver / Mover)
@{
    Name = 'Remove from HR Administrative Unit'
    Type = 'IdLE.Step.EnsureEntitlement'
    With = @{
        IdentityKey     = '{{Request.IdentityKeys.Id}}'
        Provider        = 'Entra'
        AuthSessionName = 'MicrosoftGraph'
        Entitlement     = @{ Kind = 'AdministrativeUnit'; Id = '<AU-ObjectId-GUID>' }
        State           = 'Absent'
    }
}
```

### Constraints

- Administrative Units must be **pre-created in Entra** before being referenced in a workflow. The provider validates AU existence and throws a clear, actionable error if the AU is not found.
- AUs can be referenced by **object ID (GUID)** or by **displayName**. Display-name lookup is supported for convenience, but AU display names are not guaranteed to be unique within a tenant — if multiple AUs share the same name, the provider throws an error and requires the object ID to be used instead.
- `BulkGrantEntitlements` and `BulkRevokeEntitlements` both support `Kind = 'Group'` (Graph batch path) and `Kind = 'AdministrativeUnit'` (per-item path — no Graph batch API exists for AU membership changes). Mixed-kind batches are accepted in both methods. This ensures `PruneEntitlementsEnsureKeep` works correctly for AUs (it calls both bulk methods internally).

### Graph endpoints used

| Operation | Endpoint |
| --- | --- |
| List | `GET /users/{id}/memberOf/microsoft.graph.administrativeUnit` |
| Grant | `POST /directory/administrativeUnits/{id}/members/$ref` |
| Revoke | `DELETE /directory/administrativeUnits/{id}/members/{userId}/$ref` |
| Validate AU exists by ID | `GET /directory/administrativeUnits/{id}` |
| Resolve AU by displayName | `GET /directory/administrativeUnits?$filter=displayName eq '...'` |

## Configuration

### Provider constructor / factory

- `New-IdleEntraIDIdentityProvider`

**High-signal parameters**
- `-AllowDelete` — opt-in to enable the `IdLE.Identity.Delete` capability (disabled by default for safety)

### Provider-specific options reference

This provider has **no provider-specific option bag**. Configuration is done through constructor parameters; authentication is handled by your runtime via the broker.

## Required Microsoft Graph permissions

At minimum, you typically need:
- **Users:** read/write (create/update/disable/delete if enabled)
- **Groups:** read/write memberships (if you use group entitlement steps)
- **Administrative Units:** read/write memberships (if you use Administrative Unit entitlement steps)

Exact permission names depend on your auth model (delegated vs application) and what operations you enable.

| Capability | Permission (Application) |
| --- | --- |
| List/Read users | `User.Read.All` |
| Create/update/disable users | `User.ReadWrite.All` |
| List group memberships | `Group.Read.All` |
| Grant/revoke group memberships | `GroupMember.ReadWrite.All` |
| List AU memberships | `AdministrativeUnit.Read.All` |
| Grant/revoke AU memberships | `AdministrativeUnit.ReadWrite.All` |

## Examples (canonical templates)

These are the **two** canonical Entra ID templates, intended to be embedded directly in documentation.
Mover scenarios are integrated as **optional patterns** in the Joiner template.

<CodeBlock language="powershell" title="examples/workflows/templates/entraid-joiner.psd1">{EntraJoiner}</CodeBlock>

<CodeBlock language="powershell" title="examples/workflows/templates/entraid-leaver.psd1">{EntraLeaver}</CodeBlock>

## Troubleshooting

- **401/403 from Microsoft Graph**: token missing/expired or insufficient Graph permissions for the requested operation.
- **Auth session not found**: check `AuthSessionName` matches your runtime/broker configuration.
- **Delete doesn’t work**: deletion is opt-in. Create the provider with `-AllowDelete` and only use delete with a privileged auth role.
- **Group cleanup is disruptive**: only enable revoke/remove operations when you fully understand the impact (prefer managed allow-lists).
- **Administrative Unit not found**: the AU must exist in Entra before the workflow runs. When referencing by objectId, confirm the GUID is correct. When referencing by displayName, confirm the name matches exactly and `AdministrativeUnit.Read.All` permission is granted.
- **Multiple AUs match displayName**: AU display names are not unique in Entra. If multiple AUs share the same name, use the objectId (GUID) instead to ensure deterministic lookup.

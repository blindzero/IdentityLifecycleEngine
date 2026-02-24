---
title: Provider Reference - Microsoft Entra ID (IdLE.Provider.EntraID)
sidebar_label: Entra ID
---

import CodeBlock from '@theme/CodeBlock';

import EntraJoiner from '@site/../examples/workflows/templates/entraid-joiner.psd1';
import EntraLeaver from '@site/../examples/workflows/templates/entraid-leaver.psd1';

## Summary

| Item | Value |
| --- | --- |
| **Provider name** | `EntraIDIdentityProvider` |
| **Module** | `IdLE.Provider.EntraID` |
| **Provider role** | Identity + Entitlement (Groups) |
| **Targets** | Microsoft Entra ID (formerly Azure AD) via Microsoft Graph (v1.0) |
| **Status** | Built-in |
| **PowerShell** | PowerShell 7+ |

## When to use this provider

### Use cases

- **Joiner:** create or update a user, set baseline attributes, assign baseline groups
- **Mover:** update org attributes and managed groups (covered as *optional patterns* inside the Joiner template)
- **Leaver:** disable account, revoke sessions, optional cleanup (groups, delete)

### Out of scope

- Obtaining tokens or storing secrets (handled by your runtime + AuthSessionBroker pattern)
- Exchange Online mailbox configuration (use the Exchange Online provider/steps)

## Getting started

### Requirements

- Your runtime must be able to supply a **Microsoft Graph auth session** (token/session object) to IdLE
- Graph permissions must allow the actions you intend to run (users + groups)

### Install (PowerShell Gallery)

```powershell
Install-Module IdLE.Provider.EntraID -Scope CurrentUser
```

### Import & basic check

```powershell
Import-Module IdLE.Provider.EntraID

# Create provider instance (safe defaults)
$provider = New-IdleEntraIDIdentityProvider
```

## Quickstart (minimal runnable)

```powershell
# 1) Provider instance (safe defaults)
$provider = New-IdleEntraIDIdentityProvider

# 2) Provider map (alias used in workflow files)
$providers = @{
  Identity = $provider
}
```

In a workflow template, reference your auth session via steps:

```powershell
With = @{
  AuthSessionName    = 'MicrosoftGraph'
  AuthSessionOptions = @{ Role = 'Admin' }
}
```

> Keep tokens/secrets **out of workflow files**. Resolve them in the host/runtime and provide them via the broker.

---

## Authentication

- **Auth session type:** Microsoft Graph access token (Bearer), object with `AccessToken` property, or object that can produce a token (e.g., `GetAccessToken()`)
- **Auth session name:** `MicrosoftGraph` (recommended convention) or any alias you configure
- **Session options:** optional routing key, e.g., `@{ Role = 'Admin' }` or `@{ Role = 'Tier0' }` for privileged operations

Recommended wiring in workflow steps:
- `AuthSessionName = 'MicrosoftGraph'`
- `AuthSessionOptions = @{ Role = 'Admin' }` for routing (optional)
- Use a more privileged role only for privileged actions (e.g. delete)

### Required Microsoft Graph permissions

At minimum, you typically need:
- **Users:** read/write (create/update/disable/delete if enabled)
- **Groups:** read/write memberships (if you use entitlement steps)

Exact permission names depend on your auth model (delegated vs application) and what operations you enable.

:::warning
**Security**
- Do not pass tokens or secrets in provider options or workflow files.
- Use the AuthSessionBroker pattern so credentials are resolved at runtime, outside workflow configuration.
:::

---

## Supported step types

| Step type | Capability Required | Typical use |
| --- | --- | --- |
| `IdLE.Step.CreateIdentity` | `IdLE.Identity.Create` | Create Entra ID user account |
| `IdLE.Step.EnsureAttributes` | `IdLE.Identity.Attribute.Ensure` | Update user attributes via Microsoft Graph |
| `IdLE.Step.DisableIdentity` | `IdLE.Identity.Disable` | Disable user account |
| `IdLE.Step.EnableIdentity` | `IdLE.Identity.Enable` | Enable (re-activate) user account |
| `IdLE.Step.RevokeIdentitySessions` | `IdLE.Identity.RevokeSessions` | Revoke all active sign-in sessions |
| `IdLE.Step.EnsureEntitlement` | `IdLE.Entitlement.List`, `IdLE.Entitlement.Grant`, `IdLE.Entitlement.Revoke` | Manage group memberships |
| `IdLE.Step.DeleteIdentity` | `IdLE.Identity.Delete` | Delete account — **opt-in** via `-AllowDelete` |

### Step inputs (With.*)

**`IdLE.Step.CreateIdentity`**

| Key | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `IdentityKey` | `string` | Yes | — | UPN of the user. Supports `{{Request.*}}` template expressions. |
| `Attributes` | `hashtable` | Yes | — | Attribute name → value pairs mapped to Microsoft Graph user properties (e.g., `DisplayName`, `GivenName`, `Surname`, `Mail`, `Department`, `PasswordProfile`). |
| `Provider` | `string` | No | `Identity` | Provider alias key in the providers map. |
| `AuthSessionName` | `string` | No | `Provider` value | Auth session name passed to `Context.AcquireAuthSession()`. |
| `AuthSessionOptions` | `hashtable` | No | `$null` | Data-only options for the auth session broker (e.g., `@{ Role = 'Admin' }`). |

**`IdLE.Step.EnsureAttributes`**

| Key | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `IdentityKey` | `string` | Yes | — | UPN or Object ID of the user. Supports `{{Request.*}}` template expressions. |
| `Attributes` | `hashtable` | Yes | — | Attribute name → desired value pairs. Setting to `$null` clears the attribute on the Graph user object. |
| `Provider` | `string` | No | `Identity` | Provider alias key in the providers map. |
| `AuthSessionName` | `string` | No | `Provider` value | Auth session name passed to `Context.AcquireAuthSession()`. |
| `AuthSessionOptions` | `hashtable` | No | `$null` | Data-only options for the auth session broker. |

**`IdLE.Step.DisableIdentity`** / **`IdLE.Step.EnableIdentity`** / **`IdLE.Step.RevokeIdentitySessions`** / **`IdLE.Step.DeleteIdentity`**

| Key | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `IdentityKey` | `string` | Yes | — | UPN or Object ID of the user. Supports `{{Request.*}}` template expressions. |
| `Provider` | `string` | No | `Identity` | Provider alias key in the providers map. |
| `AuthSessionName` | `string` | No | `Provider` value | Auth session name passed to `Context.AcquireAuthSession()`. |
| `AuthSessionOptions` | `hashtable` | No | `$null` | Data-only options for the auth session broker. |

> `DeleteIdentity` requires the provider to be created with `-AllowDelete`.

**`IdLE.Step.EnsureEntitlement`**

| Key | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `IdentityKey` | `string` | Yes | — | UPN or Object ID of the user. Supports `{{Request.*}}` template expressions. |
| `Entitlement` | `hashtable` | Yes | — | Entitlement descriptor: `Kind` (must be `Group`), `Id` (group Object ID), optional `DisplayName`. |
| `State` | `string` | Yes | — | Desired membership state: `Present` \| `Absent`. |
| `Provider` | `string` | No | `Identity` | Provider alias key in the providers map. |
| `AuthSessionName` | `string` | No | `Provider` value | Auth session name passed to `Context.AcquireAuthSession()`. |
| `AuthSessionOptions` | `hashtable` | No | `$null` | Data-only options for the auth session broker. |

> See the [step reference pages](../steps.md) for the full `With.*` schema and examples for each step type.

---

## Configuration

### Provider creation

- **Factory cmdlet:** `New-IdleEntraIDIdentityProvider`

**Parameters**

- `-AllowDelete` — opt-in to enable the `IdLE.Identity.Delete` capability (disabled by default for safety)
- `-Adapter` — Internal use only (dependency injection for unit tests; do not set in production)

### Provider alias usage

```powershell
$providers = @{
  Identity = New-IdleEntraIDIdentityProvider
}
```

- **Recommended alias:** `Identity`
- **Default alias expected by built-in identity/entitlement steps:** `Identity`

### Options reference

This provider has **no provider-specific option bag**. Configuration is done through constructor parameters; authentication is handled by your runtime via the broker.

---

## Operational behavior

- **Idempotency:** Yes — `CreateIdentity` skips creation if the identity already exists; `EnsureAttributes` applies only changed values; entitlement steps check current membership before acting
- **Consistency model:** Eventually consistent — some Microsoft Graph operations (user property replication, group membership) propagate with a delay
- **Throttling / rate limits:** Subject to Microsoft Graph API throttling limits; no built-in retry — delegate retry to the host
- **Retry behavior:** None built-in; host/runtime is responsible for retry on transient failures
- **Safety defaults:** Deletion is disabled unless you pass `-AllowDelete`
- **Entitlements:** Groups only (`Kind = 'Group'`; `Id` must be the group's Object ID)

---

## Examples (canonical templates)

These are the **two** canonical Entra ID templates, intended to be embedded directly in documentation.
Mover scenarios are integrated as **optional patterns** in the Joiner template.

<CodeBlock language="powershell" title="examples/workflows/templates/entraid-joiner.psd1">{EntraJoiner}</CodeBlock>

<CodeBlock language="powershell" title="examples/workflows/templates/entraid-leaver.psd1">{EntraLeaver}</CodeBlock>

---

## Troubleshooting

### Common problems

- **401/403 from Microsoft Graph**: token missing/expired or insufficient Graph permissions for the requested operation.
- **Auth session not found**: check `AuthSessionName` matches your runtime/broker configuration.
- **Delete doesn’t work**: deletion is opt-in. Create the provider with `-AllowDelete` and only use delete with a privileged auth role.
- **Group cleanup is disruptive**: only enable revoke/remove operations when you fully understand the impact (prefer managed allow-lists).

### What to collect for support

- IdLE version and `IdLE.Provider.EntraID` module version
- Redacted error message / step result details
- Microsoft Graph error code and request ID (if available)

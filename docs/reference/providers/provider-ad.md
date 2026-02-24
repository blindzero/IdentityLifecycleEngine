---
title: Provider Reference - IdLE.Provider.AD (Active Directory)
sidebar_label: Active Directory
---

import CodeBlock from '@theme/CodeBlock';

import AdJoiner from '@site/../examples/workflows/templates/ad-joiner.psd1';
import AdLeaver from '@site/../examples/workflows/templates/ad-leaver.psd1';

## Summary

| Item | Value |
| --- | --- |
| **Provider name** | `ADIdentityProvider` |
| **Module** | `IdLE.Provider.AD` |
| **Provider role** | Identity + Entitlement (Groups) |
| **Targets** | On-premises Windows Active Directory domains |
| **Status** | Built-in |
| **PowerShell** | PowerShell 7+ (Windows only) |

## When to use this provider

### Use cases

- Joiner: create/update AD users and set baseline attributes
- Mover: update org attributes and adjust managed group memberships
- Leaver: disable accounts and apply offboarding changes

### Out of scope

- Configuring connectivity/authentication itself (handled via your runtime context and the AuthSessionBroker)
- Managing non-user object types (computers, GPOs, etc.)

## Getting started

### Requirements

- **Dependencies:** Windows host with RSAT / `ActiveDirectory` module available
- **Permissions:** Account used must have rights for the operations you plan to run (create/modify users, move OUs, manage group membership)
- **Network:** Direct LDAP connectivity to the domain controller (standard AD ports)

### Install (PowerShell Gallery)

```powershell
Install-Module IdLE.Provider.AD -Scope CurrentUser
```

### Import & basic check

```powershell
Import-Module IdLE.Provider.AD

# Create provider instance (minimal, safe defaults)
$provider = New-IdleADIdentityProvider
```

## Quickstart (minimal runnable)

```powershell
# 1) Provider instance (safe defaults)
$provider = New-IdleADIdentityProvider

# 2) Provider map (alias used in workflow files)
$providers = @{
  Identity = $provider
}

# 3) Plan + execute
$plan   = New-IdlePlan -WorkflowPath './workflow.psd1' -Request $request -Providers $providers
$result = Invoke-IdlePlan -Plan $plan -Providers $providers
```

- Set the provider alias in your workflow (`With.Provider = 'Identity'` is the default)
- Reference your auth session via `With.AuthSessionName` in steps (recommended for multi-role scenarios)

---

## Authentication

- **Auth session type:** Active Directory / Windows (integrated or broker-provided credential)
- **Auth session name:** `Directory` (recommended convention) or any alias you configure
- **Session options:** optional routing key (e.g., `@{ Role = 'Tier1' }`)

By default, the AD provider uses the **run-as** identity (integrated authentication). For explicit runtime credential selection, use the **AuthSessionBroker** and pass an `AuthSession` via step configuration:

- `With.AuthSessionName` — routing key for the broker
- `With.AuthSessionOptions` — optional hashtable forwarded to the broker for session selection

:::warning
**Security**
- Do not pass credentials or secrets in provider options or workflow files.
- Ensure credentials/tokens are not written to logs or events.
:::

---

## Supported step types

The AD provider supports the common identity lifecycle and entitlement operations used by these step types:

| Step type | Capability Required | Typical use |
| --- | --- | --- |
| `IdLE.Step.CreateIdentity` | `IdLE.Identity.Create` | Create AD user account (if missing) |
| `IdLE.Step.EnsureAttributes` | `IdLE.Identity.Attribute.Ensure` | Set/update AD user attributes |
| `IdLE.Step.DisableIdentity` | `IdLE.Identity.Disable` | Disable user account (typical leaver action) |
| `IdLE.Step.EnableIdentity` | `IdLE.Identity.Enable` | Enable user account (e.g., rehire) |
| `IdLE.Step.MoveIdentity` | `IdLE.Identity.Move` | Move user to another OU |
| `IdLE.Step.EnsureEntitlement` | `IdLE.Entitlement.List`, `IdLE.Entitlement.Grant`, `IdLE.Entitlement.Revoke` | Ensure AD group memberships |
| `IdLE.Step.DeleteIdentity` | `IdLE.Identity.Delete` | Delete AD user — **opt-in** via `-AllowDelete` |

### Step inputs (With.*)

**`IdLE.Step.CreateIdentity`**

| Key | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `IdentityKey` | `string` | Yes | — | sAMAccountName, UPN, or other identity key. Supports `{{Request.*}}` template expressions. |
| `Attributes` | `hashtable` | Yes | — | Attribute name → value pairs. Named `New-ADUser` parameters are mapped directly; unknown attributes go into `OtherAttributes` using LDAP attribute names. |
| `Provider` | `string` | No | `Identity` | Provider alias key in the providers map. |
| `AuthSessionName` | `string` | No | `Provider` value | Auth session name passed to `Context.AcquireAuthSession()`. |
| `AuthSessionOptions` | `hashtable` | No | `$null` | Data-only options for the auth session broker (e.g., `@{ Role = 'Tier1' }`). |

**`IdLE.Step.EnsureAttributes`**

| Key | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `IdentityKey` | `string` | Yes | — | sAMAccountName, UPN, or other identity key. Supports `{{Request.*}}` template expressions. |
| `Attributes` | `hashtable` | Yes | — | Attribute name → desired value pairs. Setting to `$null` clears the attribute. Unknown keys go into `OtherAttributes` using LDAP attribute names. |
| `Provider` | `string` | No | `Identity` | Provider alias key in the providers map. |
| `AuthSessionName` | `string` | No | `Provider` value | Auth session name passed to `Context.AcquireAuthSession()`. |
| `AuthSessionOptions` | `hashtable` | No | `$null` | Data-only options for the auth session broker. |

**`IdLE.Step.DisableIdentity`** / **`IdLE.Step.EnableIdentity`** / **`IdLE.Step.DeleteIdentity`**

| Key | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `IdentityKey` | `string` | Yes | — | sAMAccountName, UPN, or other identity key. Supports `{{Request.*}}` template expressions. |
| `Provider` | `string` | No | `Identity` | Provider alias key in the providers map. |
| `AuthSessionName` | `string` | No | `Provider` value | Auth session name passed to `Context.AcquireAuthSession()`. |
| `AuthSessionOptions` | `hashtable` | No | `$null` | Data-only options for the auth session broker. |

> `DeleteIdentity` requires the provider to be created with `-AllowDelete`.

**`IdLE.Step.MoveIdentity`**

| Key | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `IdentityKey` | `string` | Yes | — | sAMAccountName, UPN, or other identity key. Supports `{{Request.*}}` template expressions. |
| `TargetContainer` | `string` | Yes | — | DN of the target OU (e.g., `OU=Disabled,DC=domain,DC=com`). Supports `{{Request.*}}` template expressions. |
| `Provider` | `string` | No | `Identity` | Provider alias key in the providers map. |
| `AuthSessionName` | `string` | No | `Provider` value | Auth session name passed to `Context.AcquireAuthSession()`. |
| `AuthSessionOptions` | `hashtable` | No | `$null` | Data-only options for the auth session broker. |

**`IdLE.Step.EnsureEntitlement`**

| Key | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `IdentityKey` | `string` | Yes | — | sAMAccountName, UPN, or other identity key. Supports `{{Request.*}}` template expressions. |
| `Entitlement` | `hashtable` | Yes | — | Entitlement descriptor: `Kind` (must be `Group`), `Id` (group DN or name), optional `DisplayName`. |
| `State` | `string` | Yes | — | Desired membership state: `Present` \| `Absent`. |
| `Provider` | `string` | No | `Identity` | Provider alias key in the providers map. |
| `AuthSessionName` | `string` | No | `Provider` value | Auth session name passed to `Context.AcquireAuthSession()`. |
| `AuthSessionOptions` | `hashtable` | No | `$null` | Data-only options for the auth session broker. |

> See the [step reference pages](../steps.md) for the full `With.*` schema and examples for each step type.

---

## Configuration

### Provider creation

- **Factory cmdlet:** `New-IdleADIdentityProvider`

```powershell
# Safe defaults
$provider = New-IdleADIdentityProvider

# Opt-in: allow identity deletion (advertises IdLE.Identity.Delete)
$provider = New-IdleADIdentityProvider -AllowDelete
```

### Provider alias usage

```powershell
$providers = @{
  Identity = New-IdleADIdentityProvider
}
```

- **Recommended alias:** `Identity`
- **Default alias expected by built-in identity/entitlement steps:** `Identity`

### Options reference

| Option | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `AllowDelete` | `bool` | No | `$false` | Opt-in to enable identity deletion capability (`IdLE.Identity.Delete`). Disabled by default for safety. |
| `PasswordGenerationFallbackMinLength` | `int` | No | `24` | Fallback minimum password length if domain policy cannot be read. |
| `PasswordGenerationRequireUpper` | `bool` | No | `$true` | Require uppercase letter in generated passwords (fallback). |
| `PasswordGenerationRequireLower` | `bool` | No | `$true` | Require lowercase letter in generated passwords (fallback). |
| `PasswordGenerationRequireDigit` | `bool` | No | `$true` | Require digit in generated passwords (fallback). |
| `PasswordGenerationRequireSpecial` | `bool` | No | `$true` | Require special character in generated passwords (fallback). |

---

## Operational behavior

- **Idempotency:** Yes — `CreateIdentity` skips creation if the identity already exists; `EnsureAttributes` applies only changed values; entitlement steps check current membership before acting
- **Consistency model:** Strong — AD LDAP is synchronous on the targeted domain controller
- **Throttling / rate limits:** Subject to AD LDAP limits; no built-in retry — delegate retry to the host
- **Retry behavior:** None built-in; host/runtime is responsible for retry on transient failures
- **Identity addressing:** GUID (ObjectGuid), UPN, or sAMAccountName (fallback order)
- **Safety defaults:** Deletion is disabled unless you pass `-AllowDelete`
- **Entitlements:** Groups only (`Kind = 'Group'`)

---

## Attribute handling

### CreateIdentity attributes

`IdLE.Step.CreateIdentity` maps attributes to `New-ADUser` named parameters. Attributes not listed in the named parameter set can be passed via the `OtherAttributes` container using their **LDAP attribute names** as keys.

```powershell
@{
    Name = 'Create AD user'
    Type = 'IdLE.Step.CreateIdentity'
    With = @{
        IdentityKey = '{{Request.IdentityKeys.sAMAccountName}}'
        Provider    = 'Identity'
        Attributes  = @{
            GivenName   = '{{Request.GivenName}}'
            Surname     = '{{Request.Surname}}'
            OtherAttributes = @{
                extensionAttribute1 = '{{Request.Department}}'
            }
        }
    }
}
```

> **Note:** Keys in `OtherAttributes` must be valid **LDAP attribute names** (e.g. `extensionAttribute1`, `employeeType`), not PowerShell parameter names.

### EnsureAttributes attributes

`IdLE.Step.EnsureAttributes` maps attributes to `Set-ADUser` named parameters. Setting an attribute to `$null` clears the value from the directory. Attributes not listed in the named parameter set can be set or cleared via the `OtherAttributes` container using their **LDAP attribute names** as keys.

**Custom LDAP attributes** (via OtherAttributes container):

```powershell
@{
    Name = 'Clear phone numbers'
    Type = 'IdLE.Step.EnsureAttributes'
    With = @{
        IdentityKey = '{{Request.IdentityKeys.sAMAccountName}}'
        Provider    = 'Identity'
        Attributes  = @{
            MobilePhone     = $null      # Clears the mobile attribute
            OfficePhone     = $null      # Clears the telephoneNumber attribute
            OtherAttributes = @{
                extensionAttribute1 = 'NewValue'    # Sets custom LDAP attribute
                employeeType        = $null         # Clears custom LDAP attribute
            }
        }
    }
}
```

> **Note:** Keys in `OtherAttributes` must be valid **LDAP attribute names** (e.g. `mobile`, `telephoneNumber`, `extensionAttribute1`), not PowerShell parameter names. Setting a key to `$null` clears that LDAP attribute.

---

## Examples (canonical templates)

These are the canonical, **doc-embed friendly** templates for AD.
Mover scenarios are intentionally folded into Joiner/Leaver (as optional patterns) to keep the template set small.

<CodeBlock language="powershell" title="examples/workflows/templates/ad-joiner.psd1">{AdJoiner}</CodeBlock>

<CodeBlock language="powershell" title="examples/workflows/templates/ad-leaver.psd1">{AdLeaver}</CodeBlock>

## Troubleshooting

### Common problems

- **Import fails / ActiveDirectory module missing**  
  Install RSAT / the `ActiveDirectory` module on the machine where you run IdLE.

- **Access denied / insufficient rights**  
  Ensure the account used (run-as or broker-provided credential) has the required rights for the operation (create user, set attributes, group membership, move OU).

- **Delete step doesn’t work**  
  Deletion is **opt-in**. Create the provider with `-AllowDelete` and ensure your workflow uses that provider instance.

- **Group membership changes are risky**  
  Prefer removing only explicit “managed groups” (allow-list) to avoid breaking access unexpectedly.

### What to collect for support

- IdLE version and `IdLE.Provider.AD` module version
- Redacted error message / step result details
- Windows / RSAT version, domain functional level

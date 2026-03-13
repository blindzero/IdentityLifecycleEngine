---
title: Provider Reference - IdLE.Provider.AD (Active Directory)
sidebar_label: Active Directory
---

import CodeBlock from '@theme/CodeBlock';

import AdJoiner from '@site/../examples/workflows/templates/ad-joiner.psd1';
import AdLeaver from '@site/../examples/workflows/templates/ad-leaver.psd1';

## Summary

- **Module:** `IdLE.Provider.AD`
- **Provider kind:** `Identity` + `Entitlement (Groups)`
- **Targets:** On-premises Windows Active Directory domains
- **Status:** Built-in
- **Runs on:** Windows only (requires RSAT / `ActiveDirectory` PowerShell module)
- **Default safety:** destructive operations are **opt-in** (e.g. delete)

## When to use this provider

Use this provider when your workflow needs to manage **on-premises AD user accounts**, such as:

- Joiner: create/update AD users and set baseline attributes
- Mover: update org attributes and adjust managed group memberships
- Leaver: disable accounts and apply offboarding changes

Non-goals:

- Configuring connectivity/authentication itself (handled via your runtime context and the AuthSessionBroker)
- Managing non-user object types (computers, GPOs, etc.)

## Getting started

### Requirements

- Windows host with RSAT / `ActiveDirectory` module available
- Permissions sufficient for the operations you plan to run (create/modify users, move OUs, manage group membership)

### Install (PowerShell Gallery)

```powershell
Install-Module IdLE.Provider.AD -Scope CurrentUser
```

### Import

```powershell
Import-Module IdLE.Provider.AD
```

## Quickstart

Minimal provider creation (safe defaults):

```powershell
$provider = New-IdleADIdentityProvider
```

Typical workflow usage:

- Set the provider alias in your workflow (`With.Provider = 'Directory'` is a common convention)
- Reference your auth session via `With.AuthSessionName` in steps (recommended for multi-role scenarios)

## Authentication

- By default, the AD provider uses the **run-as** identity (integrated authentication).
- For explicit runtime credential selection, use the **AuthSessionBroker** and pass an `AuthSession` via step configuration:
  - `With.AuthSessionName`
  - `With.AuthSessionOptions` (optional)

> Keep credentials/secrets **out of** workflow files. Use the broker/host to resolve them at runtime.

## Supported Step Types

The AD provider supports the common identity lifecycle and entitlement operations used by these step types:

| Step type | Typical use | Notes |
| --- | --- | --- |
| `IdLE.Step.CreateIdentity` | Create user (if missing) | Identity can be addressed by GUID, UPN, or sAMAccountName |
| `IdLE.Step.EnsureAttributes` | Set/update AD user attributes | Use placeholders from your request input |
| `IdLE.Step.DisableIdentity` | Disable user account | Typical leaver action |
| `IdLE.Step.EnableIdentity` | Enable user account | Rare (rehire) |
| `IdLE.Step.MoveIdentity` | Move user to another OU | Useful for leaver or org changes |
| `IdLE.Step.EnsureEntitlement` | Ensure group memberships | AD entitlements are **groups** |
| `IdLE.Step.RemoveEntitlement` | Remove managed groups | Prefer explicit allow-lists / managed lists |
| `IdLE.Step.DeleteIdentity` | Delete user | **Opt-in** via `-AllowDelete` (see Configuration) |

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
| `IdentityKey` | `string` | The identity key used by the workflow (GUID/UPN/sAMAccountName). |
| `Enabled` | `bool` | Derived from AD user `Enabled`. |
| `Attributes` | `hashtable` | Key/value bag; keys are strings; values are typically `string`. |

`Attributes` keys populated by this provider (when present on the AD user object):

| Attribute key | Type |
| --- | --- |
| `GivenName` | `string` |
| `Surname` | `string` |
| `DisplayName` | `string` |
| `Description` | `string` |
| `Department` | `string` |
| `Title` | `string` |
| `EmailAddress` | `string` |
| `UserPrincipalName` | `string` |
| `sAMAccountName` | `string` |
| `DistinguishedName` | `string` |

> **Attribute access**: Profile attributes are nested under the `Attributes` key. Use `...Identity.Profile.Attributes.DisplayName` in Conditions, **not** `...Identity.Profile.DisplayName`.

### Capability: `IdLE.Entitlement.List`

Writes to scoped path: `Request.Context.Providers.<ProviderAlias>.<AuthSessionKey>.Identity.Entitlements`  
Engine-defined View: `Request.Context.Views.Identity.Entitlements`  
Type: `object[]` (array of `PSCustomObject`, `PSTypeName = 'IdLE.Entitlement'`)

Each element represents one AD group membership:

| Property | Type | Notes |
| --- | --- | --- |
| `PSTypeName` | `string` | Always `IdLE.Entitlement`. |
| `Kind` | `string` | Always `Group`. |
| `Id` | `string` | AD group `DistinguishedName`. |
| `DisplayName` | `string` | AD group `Name`. |

Notes:
- The output paths are fixed by the engine and cannot be changed.
- Each entry is automatically annotated with `SourceProvider` and `SourceAuthSessionName` metadata.
- Use the global View (`Request.Context.Views.Identity.Entitlements`) in **Conditions** when you don't need to filter by provider. Use the scoped path when you need results from a specific provider only.
- See [Context Resolvers](../../use/workflows/context-resolver.md) for the full path reference.

## Configuration

### Provider factory

```powershell
# Safe defaults
$provider = New-IdleADIdentityProvider

# Opt-in: allow identity deletion (advertises IdLE.Identity.Delete)
$provider = New-IdleADIdentityProvider -AllowDelete
```

### Options reference

| Option | Type | Default | Meaning |
| --- | --- | --- | --- |
| `AllowDelete` | `bool` | `false` | Enables identity deletion capability (opt-in for safety) |
| `PasswordGenerationFallbackMinLength` | `int` | `24` | Fallback minimum length if domain policy cannot be read |
| `PasswordGenerationRequireUpper` | `bool` | `true` | Require uppercase in generated passwords (fallback) |
| `PasswordGenerationRequireLower` | `bool` | `true` | Require lowercase in generated passwords (fallback) |
| `PasswordGenerationRequireDigit` | `bool` | `true` | Require digit in generated passwords (fallback) |
| `PasswordGenerationRequireSpecial` | `bool` | `true` | Require special char in generated passwords (fallback) |

## Operational behavior

- **Identity addressing:** GUID (ObjectGuid), UPN, or sAMAccountName (fallback)
- **Safety defaults:** deletion is disabled unless you pass `-AllowDelete`
- **Entitlements:** groups only (`Kind='Group'`)

## Attribute handling

### CreateIdentity attributes

`IdLE.Step.CreateIdentity` maps attributes to `New-ADUser` named parameters. Attributes not listed in the named parameter set can be passed via the `OtherAttributes` container using their **LDAP attribute names** as keys.

```powershell
@{
    Name = 'Create AD user'
    Type = 'IdLE.Step.CreateIdentity'
    With = @{
        IdentityKey = '{{Request.IdentityKeys.sAMAccountName}}'
        Provider    = 'AD'
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
        Provider    = 'AD'
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

## Examples

These are the canonical, **doc-embed friendly** templates for AD.
Mover scenarios are intentionally folded into Joiner/Leaver (as optional patterns) to keep the template set small.

<CodeBlock language="powershell" title="examples/workflows/templates/ad-joiner.psd1">{AdJoiner}</CodeBlock>

<CodeBlock language="powershell" title="examples/workflows/templates/ad-leaver.psd1">{AdLeaver}</CodeBlock>

## Troubleshooting

- **Import fails / ActiveDirectory module missing**  
  Install RSAT / the `ActiveDirectory` module on the machine where you run IdLE.

- **Access denied / insufficient rights**  
  Ensure the account used (run-as or broker-provided credential) has the required rights for the operation (create user, set attributes, group membership, move OU).

- **Delete step doesn’t work**  
  Deletion is **opt-in**. Create the provider with `-AllowDelete` and ensure your workflow uses that provider instance.

- **Group membership changes are risky**  
  Prefer removing only explicit “managed groups” (allow-list) to avoid breaking access unexpectedly.

---
title: Provider Reference - Mock (IdLE.Provider.Mock)
sidebar_label: Mock
---

import CodeBlock from '@theme/CodeBlock';

## Summary

| Item | Value |
| --- | --- |
| **Provider name** | `MockIdentityProvider` |
| **Module** | `IdLE.Provider.Mock` |
| **Provider role** | Identity + Entitlement (in-memory) |
| **Targets** | In-memory (no external system) |
| **Status** | Built-in |
| **PowerShell** | PowerShell 7+ |

## When to use this provider

### Use cases

- Validate **workflow logic**, conditions, and error handling without touching real systems
- Validate **template placeholders** (e.g. `{{Request.Intent...}}`) in a dry-run mode
- Build demos or CI checks that should never modify production systems

### Out of scope

- Replacement for integration testing against real providers
- Performance testing or concurrency simulation

## Getting started

### Requirements

None beyond IdLE itself. The Mock provider stores everything in-memory during the workflow run.

### Install (PowerShell Gallery)

```powershell
Install-Module IdLE.Provider.Mock -Scope CurrentUser
```

### Import & basic check

```powershell
Import-Module IdLE.Provider.Mock

# Create provider instance
$provider = New-IdleMockIdentityProvider
```

## Quickstart (minimal runnable)

```powershell
# 1) Provider instance
$provider = New-IdleMockIdentityProvider

# 2) Provider map (alias used in workflow files)
$providers = @{
  Identity = $provider
}

# 3) Plan + execute — no real system calls, all state in-memory
$plan   = New-IdlePlan -WorkflowPath './workflow.psd1' -Request $request -Providers $providers
$result = Invoke-IdlePlan -Plan $plan -Providers $providers
```

---

## Authentication

No authentication is required. The Mock provider ignores `AuthSessionName` and does not require an AuthSessionBroker.

---

## Supported step types

| Step type | Capability Required | Typical use |
| --- | --- | --- |
| `IdLE.Step.EnsureAttributes` | `IdLE.Identity.Attribute.Ensure` | Set/update attributes (in-memory) |
| `IdLE.Step.DisableIdentity` | `IdLE.Identity.Disable` | Disable identity (in-memory) |
| `IdLE.Step.EnsureEntitlement` | `IdLE.Entitlement.List`, `IdLE.Entitlement.Grant`, `IdLE.Entitlement.Revoke` | Manage group memberships (in-memory) |

### Step inputs (With.*)

**`IdLE.Step.EnsureAttributes`**

| Key | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `IdentityKey` | `string` | Yes | — | Identity key (in-memory identifier). Supports `{{Request.*}}` template expressions. |
| `Attributes` | `hashtable` | Yes | — | Attribute name → desired value pairs (stored in-memory). |
| `Provider` | `string` | No | `Identity` | Provider alias key in the providers map. |
| `AuthSessionName` | `string` | No | `Provider` value | Ignored by the Mock provider. |

**`IdLE.Step.DisableIdentity`**

| Key | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `IdentityKey` | `string` | Yes | — | Identity key (in-memory identifier). Supports `{{Request.*}}` template expressions. |
| `Provider` | `string` | No | `Identity` | Provider alias key in the providers map. |
| `AuthSessionName` | `string` | No | `Provider` value | Ignored by the Mock provider. |

**`IdLE.Step.EnsureEntitlement`**

| Key | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `IdentityKey` | `string` | Yes | — | Identity key (in-memory identifier). Supports `{{Request.*}}` template expressions. |
| `Entitlement` | `hashtable` | Yes | — | Entitlement descriptor: `Kind`, `Id`, optional `DisplayName`. Stored in-memory. |
| `State` | `string` | Yes | — | Desired membership state: `Present` \| `Absent`. |
| `Provider` | `string` | No | `Identity` | Provider alias key in the providers map. |
| `AuthSessionName` | `string` | No | `Provider` value | Ignored by the Mock provider. |

> See the [step reference pages](../steps.md) for the full `With.*` schema for each step type.

---

## Configuration

### Provider creation

- **Factory cmdlet:** `New-IdleMockIdentityProvider`

This provider has no admin-facing options.

### Provider alias usage

```powershell
$providers = @{
  Identity = New-IdleMockIdentityProvider
}
```

- **Recommended alias:** `Identity`
- **Default alias expected by built-in identity/entitlement steps:** `Identity`

### Options reference

This provider has no admin-facing option bag.

---

## Operational behavior

- **Idempotency:** Yes — in-memory state is consistent within a single workflow run
- **Consistency model:** N/A — all operations are in-memory and synchronous
- **Throttling / rate limits:** None
- **Retry behavior:** N/A

> State does **not** persist across workflow runs. Each execution starts with an empty in-memory store.

---

## Examples

```powershell
# Minimal dry-run: use Mock instead of real AD or Entra ID
$providers = @{
  Identity = New-IdleMockIdentityProvider
}

$request = New-IdleRequest -LifecycleEvent Joiner -Actor $env:USERNAME -Intent @{
  UserPrincipalName = 'alice@contoso.com'
  GivenName         = 'Alice'
  Surname           = 'Smith'
}

$plan   = New-IdlePlan -WorkflowPath './joiner-workflow.psd1' -Request $request -Providers $providers
$result = Invoke-IdlePlan -Plan $plan -Providers $providers
$result.Steps
```

---

## Troubleshooting

### Common problems

- **Values don't persist across runs**: the Mock provider is in-memory per execution by design.
- **You need to test real permissions or connectivity**: switch to the real provider (AD/Entra/EXO/DirectorySync) and run in a test environment.

### What to collect for support

- IdLE version and `IdLE.Provider.Mock` module version
- Redacted workflow definition and request

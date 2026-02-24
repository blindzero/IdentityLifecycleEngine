---
title: Provider Reference - Entra Connect Directory Sync (IdLE.Provider.DirectorySync.EntraConnect)
sidebar_label: Directory Sync (Entra Connect)
---

import CodeBlock from '@theme/CodeBlock';

import EntraConnectTriggerSync from '@site/../examples/workflows/templates/directorysync-entraconnect-trigger-sync.psd1';

## Summary

| Item | Value |
| --- | --- |
| **Provider name** | `EntraConnectDirectorySyncProvider` |
| **Module** | `IdLE.Provider.DirectorySync.EntraConnect` |
| **Provider role** | DirectorySync |
| **Targets** | Entra Connect (Azure AD Connect) server with ADSync |
| **Status** | Built-in |
| **PowerShell** | PowerShell 7+ |

## When to use this provider

### Use cases

- Trigger an Entra Connect sync cycle (`Delta` or `Initial`) as part of a workflow
- Optionally wait/poll until the cycle is no longer in progress
- **Joiner:** after creating an AD identity, trigger delta sync so the object appears in Entra ID sooner
- **Operational:** run an initial sync after configuration changes (explicit, controlled)

### Out of scope

- Handling remote connectivity, authentication, or elevation itself (host/runtime responsibility)
- Replacing your monitoring/operations tooling (this is workflow orchestration)

## Getting started

### Requirements

- An Entra Connect (Azure AD Connect) server with ADSync installed (ADSync cmdlets available)
- A host/runtime that can provide an **elevated remote execution handle** to IdLE via AuthSessionBroker
- Rights to run `Start-ADSyncSyncCycle` and `Get-ADSyncScheduler` in that remote context

### Install (PowerShell Gallery)

```powershell
Install-Module IdLE.Provider.DirectorySync.EntraConnect -Scope CurrentUser
```

### Import & basic check

```powershell
Import-Module IdLE.Provider.DirectorySync.EntraConnect

# Create provider instance
$provider = New-IdleEntraConnectDirectorySyncProvider
```

## Quickstart (minimal runnable)

```powershell
# 1) Provider instance
$provider = New-IdleEntraConnectDirectorySyncProvider

# 2) Provider map (alias used in workflow files)
$providers = @{
  DirectorySync = $provider
}
```

---

## Authentication

This provider requires an AuthSession that supports remote execution and **must be elevated**.

- **Auth session type:** An object that implements `InvokeCommand(CommandName, Parameters)` — your host provides this via the AuthSessionBroker
- **Auth session name:** `EntraConnect` (recommended convention) or any alias you configure
- **Session options:** optional routing key, e.g., `@{ Role = 'EntraConnectAdmin' }`

```powershell
# Example auth session wiring in a workflow step:
With = @{
  AuthSessionName    = 'EntraConnect'
  AuthSessionOptions = @{ Role = 'EntraConnectAdmin' }
  PolicyType         = 'Delta'
}
```

> No interactive prompts are made. If the remote context is not elevated, triggering a sync cycle will fail with a privilege/elevation error.

:::warning
**Security**
- Do not embed credentials in workflow files or provider options.
- The AuthSession object must be provided by your host/runtime at execution time.
:::

---

## Supported step types

This provider advertises these capabilities:

- `IdLE.DirectorySync.Trigger`
- `IdLE.DirectorySync.Status`

| Step type | Capability Required | Typical use |
| --- | --- | --- |
| `IdLE.Step.TriggerDirectorySync` | `IdLE.DirectorySync.Trigger`, `IdLE.DirectorySync.Status` | Trigger and optionally wait for Entra Connect sync cycle |

### Step inputs (With.*)

**`IdLE.Step.TriggerDirectorySync`**

| Key | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `AuthSessionName` | `string` | Yes | — | Auth session name passed to `Context.AcquireAuthSession()`. Must resolve to an object implementing `InvokeCommand(CommandName, Parameters)`. |
| `PolicyType` | `string` | Yes | — | Sync policy type: `Delta` \| `Initial`. |
| `Provider` | `string` | No | `DirectorySync` | Provider alias key in the providers map. |
| `AuthSessionOptions` | `hashtable` | No | `$null` | Data-only options for the auth session broker (e.g., `@{ Role = 'EntraConnectAdmin' }`). |
| `Wait` | `bool` | No | `$false` | Whether to wait/poll for the sync cycle to complete before continuing. |
| `TimeoutSeconds` | `int` | No | `600` | Maximum wait time in seconds (only relevant when `Wait = $true`). |
| `PollIntervalSeconds` | `int` | No | `10` | Polling interval in seconds (only relevant when `Wait = $true`). |

> See the [step reference page](../steps/step-trigger-directory-sync.md) for the full `With.*` schema and examples.

---

## Configuration

### Provider creation

- **Factory cmdlet:** `New-IdleEntraConnectDirectorySyncProvider`

This provider has no admin-facing option bag. Configuration is done through:
- step inputs (`PolicyType`, `Wait`, `TimeoutSeconds`, `PollIntervalSeconds`)
- host configuration (remote connection and elevation)

### Provider alias usage

```powershell
$providers = @{
  DirectorySync = New-IdleEntraConnectDirectorySyncProvider
}
```

- **Recommended alias:** `DirectorySync`
- **Default alias expected by `TriggerDirectorySync` step:** `DirectorySync`

### Options reference

This provider has no admin-facing option bag.

---

## Operational behavior

- **Idempotency:** Partial — triggering a sync cycle is not idempotent; if already running, a duplicate trigger may be rejected by ADSync
- **Consistency model:** Depends on Entra Connect server state and ADSync scheduler behavior
- **Throttling / rate limits:** Subject to ADSync limits; no built-in retry
- **Retry behavior:** None built-in; host/runtime is responsible for retry on transient failures

---

## Examples (canonical template)

<CodeBlock language="powershell" title="examples/workflows/templates/directorysync-entraconnect-trigger-sync.psd1">{EntraConnectTriggerSync}</CodeBlock>

---

## Troubleshooting

### Common problems

- **"Missing privileges or elevation"**: your AuthSession must run commands in an elevated context on the Entra Connect server.
- **"AuthSession must implement InvokeCommand"**: your host must provide an AuthSession object with an `InvokeCommand()` method.
- **Get-ADSyncScheduler not found**: ensure ADSync cmdlets are available in the remote session (module installed/accessible).
- **Timeout waiting for completion**: increase `TimeoutSeconds` or check the scheduler state on the server.

### What to collect for support

- IdLE version and `IdLE.Provider.DirectorySync.EntraConnect` module version
- Redacted error message / step result details
- Entra Connect server version (ADSync module version)

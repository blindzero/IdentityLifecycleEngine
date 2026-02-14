---
title: Provider Reference - Entra Connect Directory Sync (IdLE.Provider.DirectorySync.EntraConnect)
sidebar_label: Directory Sync (Entra Connect)
---

import CodeBlock from '@theme/CodeBlock';

import EntraConnectTriggerSync from '@site/../examples/workflows/templates/directorysync-entraconnect-trigger-sync.psd1';

## Summary

- **Module:** `IdLE.Provider.DirectorySync.EntraConnect`
- **What it’s for:** Triggering and monitoring **Entra Connect (ADSync)** sync cycles on an on-prem server
- **Execution model:** Remote execution via a host-provided AuthSession (elevated context)

## When to use

Use this provider when your workflow needs to:

- Trigger an Entra Connect sync cycle (`Delta` or `Initial`)
- Optionally wait/poll until the cycle is no longer in progress

Typical use cases:

- Joiner: after creating an AD identity, trigger delta sync so the object appears in Entra ID sooner
- Operational: run an initial sync after configuration changes (explicit, controlled)

Non-goals:

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

### Import

```powershell
Import-Module IdLE.Provider.DirectorySync.EntraConnect
```

## Quickstart

Create provider:

```powershell
$provider = New-IdleEntraConnectDirectorySyncProvider
```

Register it (example convention):

```powershell
$providers = @{
  DirectorySync = $provider
}
```

## Authentication (important)

This provider requires an AuthSession that supports remote execution and **must be elevated**.

The AuthSession object must provide a method:

- `InvokeCommand(CommandName, Parameters)`

Your host/runtime should provide this session via the AuthSessionBroker and you reference it in the step via:

- `AuthSessionName = 'EntraConnect'`
- `AuthSessionOptions = @{ Role = 'EntraConnectAdmin' }` (optional routing key)

> No interactive prompts are made. If the remote context is not elevated, triggering a sync cycle will fail with a privilege/elevation error.

## Supported operations

This provider advertises these capabilities:

- `IdLE.DirectorySync.Trigger`
- `IdLE.DirectorySync.Status`

Those are typically used by step types like:

- `IdLE.Step.TriggerDirectorySync` (trigger + optional wait/poll)

## Configuration

This provider has no admin-facing option bag. Configuration is done through:
- step inputs (`PolicyType`, `Wait`, `TimeoutSeconds`, `PollIntervalSeconds`)
- host configuration (remote connection and elevation)

## Examples (canonical template)

<CodeBlock language="powershell" title="examples/workflows/templates/directorysync-entraconnect-trigger-sync.psd1">
  {EntraConnectTriggerSync}
</CodeBlock>

## Troubleshooting

- **“Missing privileges or elevation”**: your AuthSession must run commands in an elevated context on the Entra Connect server.
- **“AuthSession must implement InvokeCommand”**: your host must provide an AuthSession object with an `InvokeCommand()` method.
- **Get-ADSyncScheduler not found**: ensure ADSync cmdlets are available in the remote session (module installed/accessible).
- **Timeout waiting for completion**: increase `TimeoutSeconds` or check the scheduler state on the server.

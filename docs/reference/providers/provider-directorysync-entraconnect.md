---
title: Provider Reference - Entra Connect Directory Sync (IdLE.Provider.DirectorySync.EntraConnect)
sidebar_label: Directory Sync (Entra Connect)
---

import CodeBlock from '@theme/CodeBlock';

import EntraConnectTriggerSync from '@site/../examples/workflows/templates/directorysync-entraconnect-trigger-sync.psd1';

## Summary

- **Module:** `IdLE.Provider.DirectorySync.EntraConnect`
- **What it’s for:** Triggering and monitoring **Entra Connect (ADSync)** sync cycles on an on-prem server
- **Execution model:** Remote execution via provider-managed PSRemoting using a host-provided credential

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
- A host/runtime that can provide an **elevated credential** to IdLE via AuthSessionBroker
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

## Authentication

This provider requires an AuthSession credential ([PSCredential]) and **must be elevated**.
The provider creates and cleans up PSRemoting sessions internally.

By default, the AD provider uses the run-as identity (integrated authentication).
For explicit runtime credential selection, use the AuthSessionBroker and pass an AuthSession via step configuration:

- With.AuthSessionName
- With.AuthSessionOptions (optional)

> Keep credentials/secrets out of workflow files. Use the broker/host to resolve them at runtime.

## Supported Step Types

The Directory Sync (Entra Connect) provider supports the common identity lifecycle and entitlement operations used by these step types:

| Step type | Typical use | Notes |
| --- | --- | --- |
| `IdLE.Step.TriggerDirectorySync` | Trigger Directory Sync | Initiated by PSRemote session execution, with optional wait/poll |

## Context Resolvers

This provider does **not** support any of the allowlisted Context Resolver capabilities.

## Configuration

### Options reference

| Option | Type | Default | Meaning |
| --- | --- | --- | --- |
| `ComputerName` | `string` | `` | ComputerName for PSSession connection |
| `PolicyType` | `string` | `Delta` | `Delta` or `Full` sync policy |
| `Wait` | `bool` | `true` | Poll sync status and wait for result (or timeout) |
| `PollIntervalSeconds` | `int` | `10` | Interval in seconds to poll for sync status |
| `TimeoutSeconds` | `int` | `600` | Timeout for poll wait in seconds. Will result in `StepFailed` |

## Examples

<CodeBlock language="powershell" title="examples/workflows/templates/directorysync-entraconnect-trigger-sync.psd1">{EntraConnectTriggerSync}</CodeBlock>

## Troubleshooting

- **“Missing privileges or elevation”**: ensure the provided credential is elevated on the Entra Connect server.
- **“AuthSession must be a [PSCredential]”**: configure `New-IdleAuthSession -AuthSessionType Credential`.
- **Get-ADSyncScheduler not found**: ensure ADSync cmdlets are available on the target server.
- **Timeout waiting for completion**: increase `TimeoutSeconds` or check the scheduler state on the server.

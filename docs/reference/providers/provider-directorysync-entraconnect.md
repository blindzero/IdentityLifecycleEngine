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

There is no integrated/run-as authentication fallback; a credential-backed AuthSession must be supplied at runtime via the AuthSessionBroker.
To select the runtime credential for this provider, pass the AuthSession via step configuration:

- With.AuthSessionName
- With.AuthSessionOptions (optional)

> Keep credentials/secrets out of workflow files. Use the broker/host to resolve them at runtime.

## Supported Step Types

The Directory Sync (Entra Connect) provider supports the directory sync step types listed below:

| Step type | Typical use | Notes |
| --- | --- | --- |
| `IdLE.Step.TriggerDirectorySync` | Trigger Directory Sync | Executed via a provider-managed PSRemoting session, with optional wait/poll |

## Context Resolvers

This provider does **not** support any of the allowlisted Context Resolver capabilities.

## Configuration

This provider does **not** expose an admin-facing provider option bag.
Configuration for triggering and monitoring sync is supplied through the
`IdLE.Step.TriggerDirectorySync` step inputs via `With.*` keys.

The generic step schema does not require any `With.*` keys at schema level for this
step type. However, this provider requires specific inputs during provider validation
and execution, as noted below.

### Step input reference

| Step input | Type | Default | Meaning |
| --- | --- | --- | --- |
| `With.ComputerName` | `string` | Required by provider | ComputerName for PSSession connection |
| `With.PolicyType` | `string` | Required by provider | `Delta` or `Initial` sync policy |
| `With.Wait` | `bool` | `false` | Poll sync status and wait for result (or timeout) |
| `With.PollIntervalSeconds` | `int` | `10` | Interval in seconds to poll for sync status |
| `With.TimeoutSeconds` | `int` | `600` | Timeout for poll wait in seconds. Will result in `StepFailed` |

## Examples

<CodeBlock language="powershell" title="examples/workflows/templates/directorysync-entraconnect-trigger-sync.psd1">{EntraConnectTriggerSync}</CodeBlock>

## Troubleshooting

- **“Missing privileges or elevation”**: ensure the provided credential is elevated on the Entra Connect server.
- **“AuthSession must be a [PSCredential]”**: configure the AuthSessionBroker/host runtime to provide a credential-backed AuthSession ([PSCredential]) for this provider.
- **Get-ADSyncScheduler not found**: ensure ADSync cmdlets are available on the target server.
- **Timeout waiting for completion**: increase `TimeoutSeconds` or check the scheduler state on the server.

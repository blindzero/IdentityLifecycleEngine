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

## Authentication (important)

This provider requires an AuthSession credential ([PSCredential]) and **must be elevated**.
The provider creates and cleans up PSRemoting sessions internally.

Your host/runtime should provide this credential via the AuthSessionBroker and you reference it in the step via:

- `AuthSessionName = 'EntraConnect'`
- `ProviderInput = @{ ComputerName = 'ad-sync1.corp.local'; PolicyType = 'Delta' }`

> No interactive prompts are made. If the credential does not have elevated rights on the target server, triggering a sync cycle will fail with a privilege/elevation error.

## Supported operations

This provider advertises these capabilities:

- `IdLE.DirectorySync.Trigger`
- `IdLE.DirectorySync.Status`

Those are typically used by step types like:

- `IdLE.Step.TriggerDirectorySync` (trigger + optional wait/poll)

## Context Resolvers

This provider does **not** support any of the allowlisted Context Resolver capabilities.

Context Resolvers can only use read-only capabilities like `IdLE.Identity.Read` and `IdLE.Entitlement.List`.
This provider does not advertise these capabilities, so it cannot be used in the workflow `ContextResolvers` section.

## Configuration

This provider has no admin-facing option bag. Configuration is done through:
- provider input (`ProviderInput.ComputerName`, `ProviderInput.PolicyType`)
- step-generic inputs (`Wait`, `TimeoutSeconds`, `PollIntervalSeconds`)
- host configuration (credential broker)

## Examples (canonical template)

<CodeBlock language="powershell" title="examples/workflows/templates/directorysync-entraconnect-trigger-sync.psd1">{EntraConnectTriggerSync}</CodeBlock>

## Troubleshooting

- **“Missing privileges or elevation”**: ensure the provided credential is elevated on the Entra Connect server.
- **“AuthSession must be a [PSCredential]”**: configure `New-IdleAuthSession -AuthSessionType Credential`.
- **Get-ADSyncScheduler not found**: ensure ADSync cmdlets are available on the target server.
- **Timeout waiting for completion**: increase `TimeoutSeconds` or check the scheduler state on the server.

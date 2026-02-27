---
title: Provider Reference - Mock (IdLE.Provider.Mock)
sidebar_label: Mock
---

import CodeBlock from '@theme/CodeBlock';

## Summary

- **Module:** `IdLE.Provider.Mock`
- **What it’s for:** Running workflows **without touching real systems** (dry runs, demos, pipeline tests)
- **Provider kind:** Identity + Entitlement (in-memory)

## When to use

Use the Mock provider when you want to:

- validate **workflow logic**, conditions, and error handling
- validate **template placeholders** (e.g. `{{Request.Intent...}}`) without external dependencies
- build demos or CI checks that should never modify production systems

Non-goals:

- not a replacement for integration testing against real providers
- not meant for performance testing or concurrency simulation

## Getting started

### Requirements

None beyond IdLE itself. The Mock provider stores everything in-memory during the workflow run.

### Install (PowerShell Gallery)

```powershell
Install-Module IdLE.Provider.Mock -Scope CurrentUser
```

### Import

```powershell
Import-Module IdLE.Provider.Mock
```

## Quickstart

Create the provider and register it under a workflow alias (example):

```powershell
$providers = @{
  Identity = New-IdleMockIdentityProvider
}
```

## Authentication

No authentication is required. The Mock provider ignores `AuthSessionName`.

## Supported operations

- Identity: create/update attributes (in-memory)
- Entitlements: ensure/remove group memberships (in-memory)

## Context Resolvers

This provider supports Context Resolvers for the allowlisted, read-only capabilities below.

### Capability: `IdLE.Identity.Read`

Writes to: `Request.Context.Identity.Profile`  
Type: `PSCustomObject` (`PSTypeName = 'IdLE.Identity'`)

Top-level properties:

| Property | Type | Notes |
| --- | --- | --- |
| `PSTypeName` | `string` | Always `IdLE.Identity`. |
| `IdentityKey` | `string` | The identity key used by the workflow. |
| `Enabled` | `bool` | Stored boolean value (defaults to `$true` when created on demand). |
| `Attributes` | `hashtable` | Free-form key/value bag stored in the mock provider store. |

Mock-specific behavior:
- Missing identities are created **on-demand** on first `GetIdentity` call (planning-time resolvers may therefore “create” a record in the in-memory store).
- `Attributes` is whatever your tests/demos put into the store (commonly `string` values).

### Capability: `IdLE.Entitlement.List`

Writes to: `Request.Context.Identity.Entitlements`  
Type: `object[]` (array of `PSCustomObject`, `PSTypeName = 'IdLE.Entitlement'`)

Each element is normalized via `ConvertToEntitlement`:

| Property | Type | Notes |
| --- | --- | --- |
| `PSTypeName` | `string` | Always `IdLE.Entitlement`. |
| `Kind` | `string` | Required; non-empty. |
| `Id` | `string` | Required; non-empty. |
| `DisplayName` | `string` or `$null` | Optional. |

Notes:
- The output paths are fixed by the engine and cannot be changed.
- Use these values in **Conditions**, **Preconditions**, and **Templates** (resolved during planning).

## Configuration

This provider has no admin-facing options.

## Troubleshooting

- **Values don’t persist across runs**: the Mock provider is in-memory per execution by design.
- **You need to test real permissions or connectivity**: switch to the real provider (AD/Entra/EXO/DirectorySync) and run in a test environment.

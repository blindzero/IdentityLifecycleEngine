---
title: Provider Reference - Mock (IdLE.Provider.Mock)
sidebar_label: Mock
---

import CodeBlock from '@theme/CodeBlock';

import MockIdentityAndEntitlements from '@site/../examples/workflows/mock/mock-identity-and-entitlements.psd1';

## Summary

- **Module:** `IdLE.Provider.Mock`
- **What it’s for:** Running workflows **without touching real systems** (dry runs, demos, pipeline tests)
- **Provider kind:** Identity + Entitlement (in-memory)

## When to use

Use the Mock provider when you want to:

- validate **workflow logic**, conditions, and error handling
- validate **template placeholders** (e.g. `{{Request.Input...}}`) without external dependencies
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

## Configuration

This provider has no admin-facing options.

## Example (canonical)

<CodeBlock language="powershell" title="examples/workflows/mock/mock-identity-and-entitlements.psd1">
  {MockIdentityAndEntitlements}
</CodeBlock>

## Troubleshooting

- **Values don’t persist across runs**: the Mock provider is in-memory per execution by design.
- **You need to test real permissions or connectivity**: switch to the real provider (AD/Entra/EXO/DirectorySync) and run in a test environment.

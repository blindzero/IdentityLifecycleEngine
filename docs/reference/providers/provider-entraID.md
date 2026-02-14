---
title: Provider Reference - Microsoft Entra ID (IdLE.Provider.EntraID)
sidebar_label: Entra ID
---

import CodeBlock from '@theme/CodeBlock';

import EntraJoiner from '@site/../examples/workflows/templates/entraid-joiner.psd1';
import EntraLeaver from '@site/../examples/workflows/templates/entraid-leaver.psd1';

## Summary

- **Module:** `IdLE.Provider.EntraID`
- **What it’s for:** Entra ID user lifecycle + group entitlements (Microsoft Graph API)
- **Targets:** Microsoft Entra ID (formerly Azure AD) via Microsoft Graph (v1.0)

## When to use

Use this provider when your workflow needs to manage **Entra ID user accounts**, for example:

- **Joiner:** create or update a user, set baseline attributes, assign baseline groups
- **Mover:** update org attributes and managed groups (covered as *optional patterns* inside the Joiner template)
- **Leaver:** disable account, revoke sessions, optional cleanup (groups, delete)

Non-goals:

- Obtaining tokens or storing secrets (handled by your runtime + AuthSessionBroker pattern)
- Exchange Online mailbox configuration (use the Exchange Online provider/steps)

## Getting started

### Requirements

- Your runtime must be able to supply a **Microsoft Graph auth session** (token/session object) to IdLE
- Graph permissions must allow the actions you intend to run (users + groups)

### Install (PowerShell Gallery)

```powershell
Install-Module IdLE.Provider.EntraID -Scope CurrentUser
```

### Import

```powershell
Import-Module IdLE.Provider.EntraID
```

## Quickstart

Create provider (safe defaults):

```powershell
$provider = New-IdleEntraIDIdentityProvider
```

Typical alias pattern:

```powershell
$providers = @{
  Identity = $provider
}
```

In a workflow template, reference your auth session via steps (example):

```powershell
With = @{
  AuthSessionName    = 'MicrosoftGraph'
  AuthSessionOptions = @{ Role = 'Admin' }
}
```

> Keep tokens/secrets **out of workflow files**. Resolve them in the host/runtime and provide them via the broker.

## Authentication

This provider expects Graph authentication to be supplied at runtime (AuthSessionBroker pattern). Common session shapes used by hosts include:

- raw access token string (Bearer token)
- object with an `AccessToken` property
- object that can produce a token (e.g., `GetAccessToken()`)

Recommended wiring in examples:
- `AuthSessionName = 'MicrosoftGraph'`
- `AuthSessionOptions = @{ Role = 'Admin' }` for routing (optional)
- Use a more privileged role only for privileged actions (e.g. delete)

## Configuration

### Provider constructor / factory

- `New-IdleEntraIDIdentityProvider`

**High-signal parameters**
- `-AllowDelete` — opt-in to enable the `IdLE.Identity.Delete` capability (disabled by default for safety)

### Provider-specific options reference

This provider has **no provider-specific option bag**. Configuration is done through constructor parameters; authentication is handled by your runtime via the broker.

## Required Microsoft Graph permissions

At minimum, you typically need:
- **Users:** read/write (create/update/disable/delete if enabled)
- **Groups:** read/write memberships (if you use entitlement steps)

Exact permission names depend on your auth model (delegated vs application) and what operations you enable.

## Examples (canonical templates)

These are the **two** canonical Entra ID templates, intended to be embedded directly in documentation.
Mover scenarios are integrated as **optional patterns** in the Joiner template.

<CodeBlock language="powershell" title="examples/workflows/templates/entraid-joiner.psd1">
  {EntraJoiner}
</CodeBlock>

<CodeBlock language="powershell" title="examples/workflows/templates/entraid-leaver.psd1">
  {EntraLeaver}
</CodeBlock>

## Troubleshooting

- **401/403 from Microsoft Graph**: token missing/expired or insufficient Graph permissions for the requested operation.
- **Auth session not found**: check `AuthSessionName` matches your runtime/broker configuration.
- **Delete doesn’t work**: deletion is opt-in. Create the provider with `-AllowDelete` and only use delete with a privileged auth role.
- **Group cleanup is disruptive**: only enable revoke/remove operations when you fully understand the impact (prefer managed allow-lists).

---
title: Provider Reference - Exchange Online (IdLE.Provider.ExchangeOnline)
sidebar_label: Exchange Online
---

import CodeBlock from '@theme/CodeBlock';

import ExoJoinerMailboxBaseline from '@site/../examples/workflows/templates/exo-joiner.psd1';
import ExoLeaverMailboxOffboarding from '@site/../examples/workflows/templates/exo-leaver.psd1';

## Summary

- **Module:** `IdLE.Provider.ExchangeOnline`
- **What it’s for:** Exchange Online mailbox configuration (type conversion, Out of Office, delegate permissions, mailbox info)
- **Targets:** Exchange Online via `ExchangeOnlineManagement` v3+ cmdlets (PowerShell 7+ compatible)
- **Identity keys:** UPN (recommended), SMTP address, mailbox identifiers (provider-specific)

## When to use

Use this provider when your workflows need to manage **mailbox settings** in Exchange Online, for example:

- read mailbox info (type, primary SMTP, identifiers)
- apply a safe baseline at onboarding (verify mailbox + ensure expected type)
- convert mailbox type (e.g. user → shared for leavers)
- set Out of Office messages (internal/external) and audience
- converge delegate permissions (FullAccess, SendAs, SendOnBehalf)

Non-goals:

- establishing the Exchange Online connection (host/runtime responsibility)
- managing identity objects (use AD / Entra ID providers for accounts)

## Getting started

### Requirements

- `ExchangeOnlineManagement` v3.0+ module available on the execution host (supports PowerShell 7+)
- A host/runtime that establishes an Exchange Online session (delegated or app-only)
- Permissions for the mailbox operations you intend to run (conversion, OOO, permissions, etc.)

> **PowerShell 7+ compatibility:** `ExchangeOnlineManagement` v3.0.0 and later support PowerShell 7+ on
> Windows, macOS, and Linux via REST-based cmdlets. The “Windows only” limitation in earlier versions
> applied to certificate-based app-only auth; the module itself runs cross-platform from v3.0 onwards.

### Install (PowerShell Gallery)

```powershell
Install-Module IdLE.Provider.ExchangeOnline -Scope CurrentUser
```

### Import

```powershell
Import-Module IdLE.Provider.ExchangeOnline
```

## Quickstart

Create provider and register it (example convention):

```powershell
$providers = @{
  ExchangeOnline = New-IdleExchangeOnlineProvider
}
```

## Authentication

This provider does **not** authenticate by itself.

Your host/runtime must establish the Exchange Online session and (optionally) route it via the AuthSessionBroker.
Mailbox steps typically reference that session via:

- `AuthSessionName = 'ExchangeOnline'`
- `AuthSessionOptions = @{ Role = 'Admin' }` (optional routing key)

> Keep credentials/secrets **out of workflow files**. Resolve them in the host/runtime and provide them via the broker.

## Supported Step Types

Common step types using this provider include:

| Step Type | Capability Required | Description |
| --- | --- | --- |
| `IdLE.Step.Mailbox.GetInfo` | `IdLE.Mailbox.Info.Read` | Read mailbox details |
| `IdLE.Step.Mailbox.EnsureType` | `IdLE.Mailbox.Type.Ensure` | Convert mailbox type |
| `IdLE.Step.Mailbox.EnsureOutOfOffice` | `IdLE.Mailbox.OutOfOffice.Ensure` | Configure Out of Office |
| `IdLE.Step.Mailbox.EnsurePermissions` | `IdLE.Mailbox.Permissions.Ensure` | Converge delegate permissions |

### Delegate permissions example

```powershell
@{
    Name = 'Set Shared Mailbox Permissions'
    Type = 'IdLE.Step.Mailbox.EnsurePermissions'
    With = @{
        Provider    = 'ExchangeOnline'
        IdentityKey = 'shared@contoso.com'
        Permissions = @(
            @{ AssignedUser = 'user1@contoso.com'; Right = 'FullAccess';   Ensure = 'Present' }
            @{ AssignedUser = 'user2@contoso.com'; Right = 'SendAs';       Ensure = 'Present' }
            @{ AssignedUser = 'leaver@contoso.com'; Right = 'FullAccess';  Ensure = 'Absent'  }
        )
    }
}
```

Supported rights: `FullAccess`, `SendAs`, `SendOnBehalf`.
Each entry requires `AssignedUser` (UPN/SMTP), `Right`, and `Ensure` (`Present` or `Absent`).

## Configuration

No admin-facing provider options.

## Examples (canonical templates)

To keep provider documentation focused and consistent, this page embeds only the **canonical** Exchange Online templates:

<CodeBlock language="powershell" title="examples/workflows/templates/exo-joiner.psd1">{ExoJoinerMailboxBaseline}</CodeBlock>

<CodeBlock language="powershell" title="examples/workflows/templates/exo-leaver.psd1">{ExoLeaverMailboxOffboarding}</CodeBlock>

## Troubleshooting

- **Module not found**: install `ExchangeOnlineManagement` on the execution host.
- **Not connected**: ensure the host establishes an Exchange Online session before IdLE runs.
- **Access denied**: the session identity must have permission to change mailbox settings.
- **OOO formatting issues**: use `MessageFormat = 'Html'` and validate HTML in a test mailbox first.
- **Permission changes not applied**: ensure the session identity has the *Mail Recipients* management role (or Exchange Administrator) required for `Add/Remove-MailboxPermission` and `Add/Remove-RecipientPermission`.

## Scenarios (link-only)

Cross-provider orchestration examples are valuable, but should not be embedded in a single provider reference page.
Keep them as **link-only** and collect them on a central Examples/Scenarios page:

- `examples/workflows/templates/entraid-exo-leaver.psd1`

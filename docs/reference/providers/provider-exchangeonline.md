---
title: Provider Reference - Exchange Online (IdLE.Provider.ExchangeOnline)
sidebar_label: Exchange Online
---

import CodeBlock from '@theme/CodeBlock';

import ExoJoinerMailboxBaseline from '@site/../examples/workflows/templates/exo-joiner.psd1';
import ExoLeaverMailboxOffboarding from '@site/../examples/workflows/templates/exo-leaver.psd1';

## Summary

| Item | Value |
| --- | --- |
| **Provider name** | `ExchangeOnlineProvider` |
| **Module** | `IdLE.Provider.ExchangeOnline` |
| **Provider role** | Messaging |
| **Targets** | Exchange Online via `ExchangeOnlineManagement` v3+ (PowerShell 7+) |
| **Status** | Built-in |
| **PowerShell** | PowerShell 7+ |

---

## When to use this provider

### Use cases

- Read mailbox details (type, primary SMTP address, identifiers)
- Apply a safe baseline at onboarding (verify mailbox exists, ensure expected type)
- Convert mailbox type (e.g. user → shared for leavers)
- Set Out of Office messages (internal/external) and audience
- Converge delegate permissions (FullAccess, SendAs, SendOnBehalf)

### Out of scope

- Establishing the Exchange Online session (host/runtime responsibility — see [Authentication](#authentication))
- Creating or deleting mailboxes (use Entra ID / AD providers for account lifecycle)
- Managing identity objects or directory attributes (use AD / Entra ID providers)

---

## Getting started

### Requirements

- **Module:** `ExchangeOnlineManagement` v3.0+ installed on the execution host
- **Session:** An Exchange Online session must be established **before** IdLE runs (call `Connect-ExchangeOnline` in your host/runtime)
- **Permissions:** The session identity must have rights for the mailbox operations you intend to run

> **PowerShell 7+ compatibility:** `ExchangeOnlineManagement` v3.0+ supports PowerShell 7+ on Windows, macOS, and Linux via REST-based cmdlets.

### Install (PowerShell Gallery)

```powershell
Install-Module IdLE.Provider.ExchangeOnline -Scope CurrentUser
```

### Import & basic check

```powershell
Import-Module IdLE.Provider.ExchangeOnline

# Create provider instance
$provider = New-IdleExchangeOnlineProvider
```

The provider runs a one-time prerequisites check at construction and emits `Write-Warning` if the Exchange Online session is not established. See [Troubleshooting](#troubleshooting) if this fails.

---

## Quickstart (minimal runnable)

```powershell
# 1) Establish Exchange Online session (host responsibility — outside IdLE)
Connect-ExchangeOnline -UserPrincipalName admin@contoso.com

# 2) Provider instance
$provider = New-IdleExchangeOnlineProvider

# 3) Provider map (alias used in workflow files)
$providers = @{
  ExchangeOnline = $provider
}

# 4) Plan + execute
$plan   = New-IdlePlan -WorkflowPath './workflow.psd1' -Request $request -Providers $providers
$result = Invoke-IdlePlan -Plan $plan -Providers $providers
```

---

## Authentication

This provider does **not** authenticate by itself. Your host/runtime must establish the Exchange Online session before IdLE runs.

- **Auth session name:** `ExchangeOnline`
- **Auth session options:** `@{ Role = 'Admin' }` (optional routing key)

Workflow steps reference the session via:

```powershell
With = @{
  AuthSessionName    = 'ExchangeOnline'
  AuthSessionOptions = @{ Role = 'Admin' }
}
```

### Token requirements (delegated access)

When using delegated (user) authentication, mint the token for the Exchange Online resource:

```powershell
# Interactive (delegated) — requires user interaction at a browser prompt
$token = Get-MsalToken `
    -ClientId '<app-id>' `
    -TenantId '<tenant-id>' `
    -Scopes 'https://outlook.office365.com/.default' `
    -DeviceCode

Connect-ExchangeOnline -AccessToken $token.AccessToken -UserPrincipalName admin@contoso.com
```

> **Note:** `-DeviceCode` is interactive and requires a user to authenticate via a browser. For **automated/unattended** scenarios, use app-only authentication with a certificate:
>
> ```powershell
> Connect-ExchangeOnline -CertificateThumbprint '<thumbprint>' -AppId '<app-id>' -Organization '<tenant>.onmicrosoft.com'
> ```

The token's `scp` claim must include at least one of:
- `https://outlook.office365.com/Exchange.Manage` — full mailbox management (delegated)
- `Exchange.ManageAsApp` — app-only/service principal access

> **Note:** The `.default` scope requests all permissions pre-consented on the app registration. Make sure the EXO delegated permissions are granted in your Entra ID app.

:::warning
**Security**
- Do not pass secrets or access tokens in provider options or workflow files.
- Ensure credentials/tokens are not written to logs or events.
- The provider redacts token values from error messages automatically.
:::

---

## Supported step types

| Step Type | Capability Required | Description |
| --- | --- | --- |
| `IdLE.Step.Mailbox.GetInfo` | `IdLE.Mailbox.Info.Read` | Read mailbox details |
| `IdLE.Step.Mailbox.EnsureType` | `IdLE.Mailbox.Type.Ensure` | Convert mailbox type (User/Shared/Room/Equipment) |
| `IdLE.Step.Mailbox.EnsureOutOfOffice` | `IdLE.Mailbox.OutOfOffice.Ensure` | Configure Out of Office (enabled/disabled/scheduled) |
| `IdLE.Step.Mailbox.EnsurePermissions` | `IdLE.Mailbox.Permissions.Ensure` | Converge delegate permissions |

---

## Configuration

### Provider creation

- **Factory cmdlet:** `New-IdleExchangeOnlineProvider`

**Parameters**

- `-Adapter` — Internal use only (dependency injection for unit tests; do not set in production)

### Provider alias usage

```powershell
$providers = @{
  ExchangeOnline = New-IdleExchangeOnlineProvider
}
```

- **Recommended alias:** `ExchangeOnline`
- **Default alias expected by mailbox steps:** `ExchangeOnline`

### Options reference

This provider has no admin-facing option bag. Authentication is handled by your runtime via the AuthSessionBroker.

---

## Operational behavior

- **Idempotency:** Yes — all `Ensure*` methods check current state before making changes; unchanged state = `Changed = $false`
- **Consistency model:** Depends on Exchange Online replication (eventual consistency for permission changes)
- **Throttling / rate limits:** Subject to Exchange Online service limits; no built-in retry — delegate retry to the host
- **Retry behavior:** None built-in; host/runtime is responsible for retry on transient failures

---

## Examples (canonical templates)

<CodeBlock language="powershell" title="examples/workflows/templates/exo-joiner.psd1">{ExoJoinerMailboxBaseline}</CodeBlock>

<CodeBlock language="powershell" title="examples/workflows/templates/exo-leaver.psd1">{ExoLeaverMailboxOffboarding}</CodeBlock>

### Delegate permissions example

```powershell
@{
    Name = 'Set Shared Mailbox Permissions'
    Type = 'IdLE.Step.Mailbox.EnsurePermissions'
    With = @{
        Provider    = 'ExchangeOnline'
        IdentityKey = 'shared@contoso.com'
        Permissions = @(
            @{ AssignedUser = 'user1@contoso.com';  Right = 'FullAccess'; Ensure = 'Present' }
            @{ AssignedUser = 'user2@contoso.com';  Right = 'SendAs';     Ensure = 'Present' }
            @{ AssignedUser = 'leaver@contoso.com'; Right = 'FullAccess'; Ensure = 'Absent'  }
        )
    }
}
```

Supported rights: `FullAccess`, `SendAs`, `SendOnBehalf`.
Each entry requires `AssignedUser` (UPN/SMTP), `Right`, and `Ensure` (`Present` or `Absent`).

### More examples

- `examples/workflows/templates/entraid-exo-leaver.psd1` — cross-provider leaver (Entra ID + Exchange Online)

---

## Troubleshooting

### Common problems

- **`ExchangeOnlineManagement` module not installed**
  → Install it: `Install-Module ExchangeOnlineManagement -Scope CurrentUser`

- **Provider warns "No active Exchange Online session"**
  → `Connect-ExchangeOnline` was not called before creating the provider.
  Run `Connect-ExchangeOnline -UserPrincipalName admin@contoso.com` in your host/runtime first.

- **`Get-EXOMailbox` not found / module not imported**
  → Module is installed but not imported in this session: `Import-Module ExchangeOnlineManagement`

- **`Get-Mailbox` not recognized (session proxy cmdlet missing)**
  → No active Exchange Online session. Call `Connect-ExchangeOnline` before using the provider.

- **`Unauthorized` / 401 when using `-AccessToken`**
  → Token is not scoped for Exchange Online. Ensure you requested scopes for `https://outlook.office365.com/.default`, not `https://graph.microsoft.com/.default`.
  Verify the token's `scp` claim contains `Exchange.Manage` or `Exchange.ManageAsApp`.

- **Access denied when changing mailbox settings**
  → The session identity must have the *Mail Recipients* management role (or Exchange Administrator) for mailbox changes, and *Recipient Management* for permission changes.

- **OOO formatting issues**
  → Use `MessageFormat = 'Html'` and validate HTML in a test mailbox first. The provider normalizes HTML before comparing for idempotency.

- **Permission changes not visible immediately**
  → Exchange Online replication is eventually consistent; allow a few minutes for changes to propagate.

### What to collect for support

- IdLE version, `IdLE.Provider.ExchangeOnline` module version
- `ExchangeOnlineManagement` module version
- Redacted error message (the provider automatically redacts tokens from error output)
- Whether using delegated or app-only auth (without sharing credentials)

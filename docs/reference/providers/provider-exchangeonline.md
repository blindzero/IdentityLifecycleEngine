---
title: Provider Reference - IdLE.Provider.ExchangeOnline
sidebar_label: ExchangeOnline
---

## Purpose

This provider manages Exchange Online mailbox configuration and Out of Office settings as part of IdLE workflows.

---
## Summary

- **Provider name:** ExchangeOnline
- **Module:** `IdLE.Provider.ExchangeOnline`
- **Provider kind:** Messaging
- **Targets:** Exchange Online (ExchangeOnlineManagement cmdlets)
- **Status:** First-party (bundled)
- **Since:** 0.9.0
- **Compatibility:** PowerShell 7+ (IdLE requirement)

---

## What this provider does

- **Primary responsibilities:**
  - Read mailbox information (type, primary SMTP, UPN, GUID).
  - Converge mailbox type (User/Shared/Room/Equipment).
  - Converge Out of Office configuration.
- **Out of scope / non-goals:**
  - Establishing an Exchange Online session (handled by the host/broker).
  - Managing identity objects (use an identity provider such as AD or EntraID).

---

## Contracts and capabilities

### Contracts implemented

| Contract | Used by steps for | Notes |
| --- | --- | --- |
| Mailbox provider (implicit) | Read mailbox info, ensure mailbox type, ensure Out of Office | Methods are exposed as script methods on the provider object. |

### Capability advertisement (`GetCapabilities()`)

- **Implements `GetCapabilities()`**: Yes
- **Capabilities returned (stable identifiers):**
  - `IdLE.Mailbox.Info.Read`
  - `IdLE.Mailbox.Type.Ensure`
  - `IdLE.Mailbox.OutOfOffice.Ensure`

---

## Authentication and session acquisition

> Providers must not prompt for auth. Use the host-provided broker contract.

- **Auth session name(s) requested via `Context.AcquireAuthSession(...)`:**
  - Typically the step passes `With.AuthSessionName` (if present). For built-in mailbox steps, if `With.AuthSessionName` is absent, it defaults to the provider alias (commonly `ExchangeOnline`).
- **Session options (data-only):**
  - The provider does not interpret options; they are used by the host/broker to select credentials/route to a tenant/session.
- **Required `AuthSessionType`:** `OAuth`

The ExchangeOnline provider uses OAuth-based authentication via Exchange Online PowerShell. When creating the `AuthSessionBroker`, specify `AuthSessionType = 'OAuth'` to indicate token-based authentication is expected.

:::warning

**Security notes**

- Do not pass secrets in workflow/provider options.
- Ensure token/credential objects are not emitted in events.

:::

### Auth examples

**A) Delegated auth (interactive) – connect once in the host**

```powershell
# Host responsibility:
Connect-ExchangeOnline -UserPrincipalName 'admin@contoso.com'

$providers = @{
  ExchangeOnline = New-IdleExchangeOnlineProvider
}
```

**B) App-only (certificate) – connect once in the host**

```powershell
# Host responsibility:
Connect-ExchangeOnline `
  -AppId '00000000-0000-0000-0000-000000000000' `
  -Organization 'contoso.onmicrosoft.com' `
  -CertificateThumbprint 'THUMBPRINT'

$providers = @{
  ExchangeOnline = New-IdleExchangeOnlineProvider
}
```

**C) Multi-connection routing (advanced)**

If you need **multiple** Exchange Online sessions (e.g., multiple tenants), implement a custom
`AuthSessionBroker` that returns an **AuthSession** object understood by your host (for example,
an object that selects the right connection context before invoking cmdlets). The provider itself
does not create or own sessions.

---

## Configuration

### Provider constructor / factory

- **Public constructor cmdlet(s):**
  - `New-IdleExchangeOnlineProvider` — creates an Exchange Online mailbox provider.

**Parameters (high signal only)**

- `-Adapter <object>` — dependency injection hook for tests (optional).

> Do not copy full comment-based help here. Link to the cmdlet reference.

### Provider bag / alias usage

```powershell
$providers = @{
  ExchangeOnline = (New-IdleExchangeOnlineProvider)
}
```

- **Recommended alias pattern:** `ExchangeOnline` (or role-based, e.g. `Messaging`)
- **Default alias expected by built-in steps (if any):** `ExchangeOnline` (Mailbox steps default to this when `With.Provider` is not provided)

---

## Provider-specific options reference

This provider has no dedicated data-only `-Options` surface. Session selection is done via:

- `With.AuthSessionName`
- `With.AuthSessionOptions` (data-only hashtable, validated by the engine/steps)

---

## Operational behavior

### Idempotency and consistency

- **Idempotent operations:** Yes (for `Ensure*` methods; no-op when already in desired state)
- **Consistency model:** Depends on Exchange Online / service latency
- **Concurrency notes:** Exchange Online can throttle; retries are delegated to the host/workflow design.

### Error mapping and retry behavior

- **Common error categories:** NotFound, PermissionDenied, Throttled
- **Retry strategy:** None in the provider (delegate retries/backoff to the host if needed)

---

## Observability

- **Events emitted by provider (if any):** None (steps emit events via the execution context).
- **Sensitive data redaction:** IdLE redacts secrets at output boundaries; providers should avoid returning secret material.

---

## Examples

### Minimal host usage

```powershell
# 1) Create provider instance
$provider = New-IdleExchangeOnlineProvider

# 2) Build provider map
$providers = @{ ExchangeOnline = $provider }

# 3) Plan + execute
$plan = New-IdlePlan -WorkflowPath <path> -Request <request> -Providers $providers
$result = Invoke-IdlePlan -Plan $plan -Providers $providers
```

### Example workflow snippet

```powershell
@{
  Steps = @(
    @{
      Name = 'Ensure mailbox type'
      Type = 'IdLE.Step.Mailbox.Type.Ensure'
      With = @{
        Provider    = 'ExchangeOnline'
        IdentityKey = 'user@contoso.com'
        MailboxType = 'Shared'
        # AuthSessionName is optional; defaults to the provider alias if omitted
        # AuthSessionOptions = @{ ... }
      }
    }
  )
}
```

### OOF with template variables and dynamic manager attributes

This example shows how to use template variables (`{{...}}`) in Out of Office messages
with dynamic user attributes (e.g., manager information). Templates are resolved during
plan building against the request object.

**Important:** Manager lookup is performed **host-side**, not inside the step. This
maintains the security boundary: steps do not perform directory lookups.

**Host enrichment (example using AD):**

```powershell
# 1. Retrieve user and manager details from AD
$user = Get-ADUser -Identity 'max.power' -Properties Manager
$mgr = $null

if ($user.Manager) {
  $mgr = Get-ADUser -Identity $user.Manager -Properties DisplayName, Mail
}

# 2. Build request with manager data in DesiredState
$req = New-IdleLifecycleRequest `
  -LifecycleEvent 'Leaver' `
  -Actor $env:USERNAME `
  -Input @{ UserPrincipalName = 'max.power@contoso.com' } `
  -DesiredState @{
    Manager = @{
      DisplayName = $mgr.DisplayName
      Mail        = $mgr.Mail
    }
  }

# 3. Plan and execute
$plan = New-IdlePlan -WorkflowPath './leaver-workflow.psd1' -Request $req -Providers $providers
$result = Invoke-IdlePlan -Plan $plan -Providers $providers
```

**Workflow step using templates:**

```powershell
@{
  Name = 'Set Exchange OOF'
  Type = 'IdLE.Step.Mailbox.OutOfOffice.Ensure'
  With = @{
    Provider        = 'ExchangeOnline'
    IdentityKey     = @{ ValueFrom = 'Request.Input.UserPrincipalName' }
    Config          = @{
      Mode            = 'Enabled'
      InternalMessage = 'This mailbox is no longer monitored. Please contact {{Request.DesiredState.Manager.DisplayName}} ({{Request.DesiredState.Manager.Mail}}).'
      ExternalMessage = 'This mailbox is no longer monitored. Please contact {{Request.DesiredState.Manager.Mail}}.'
      ExternalAudience = 'All'
    }
  }
}
```

**Alternative (using Entra ID / Microsoft Graph):**

```powershell
# Host enrichment using Microsoft Graph
Connect-MgGraph -Scopes 'User.Read.All'

$user = Get-MgUser -UserId 'max.power@contoso.com' -Property 'Manager'
$mgr = if ($user.Manager.Id) {
  Get-MgUser -UserId $user.Manager.Id -Property 'DisplayName', 'Mail'
} else { $null }

$req = New-IdleLifecycleRequest `
  -LifecycleEvent 'Leaver' `
  -Actor $env:USERNAME `
  -Input @{ UserPrincipalName = 'max.power@contoso.com' } `
  -DesiredState @{
    Manager = @{
      DisplayName = $mgr.DisplayName
      Mail        = $mgr.Mail
    }
  }
```

**Step type alias:**

You can use `IdLE.Step.Mailbox.EnsureOutOfOffice` as an alternative to
`IdLE.Step.Mailbox.OutOfOffice.Ensure` (both resolve to the same handler).

---

## Limitations and known issues

- Requires the `ExchangeOnlineManagement` PowerShell module at runtime.
- The host must establish or broker a usable Exchange Online session; the provider does not connect interactively.

---

## Testing

- **Unit tests:** `tests/Providers/ExchangeOnlineProvider.Tests.ps1`
- **Contract tests:** Provider contract tests validate implementation compliance
- **Known CI constraints:** Tests use mock cmdlet layer; no live Exchange Online calls in CI

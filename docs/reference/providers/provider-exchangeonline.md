---
title: Provider Reference - IdLE.Provider.ExchangeOnline
sidebar_label: ExchangeOnline
---

> **Purpose:** This page is a **reference** for a specific provider implementation.
> Keep it factual and contract-oriented. Put conceptual explanations elsewhere and link to them.

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
      Type = 'IdLE.Step.MailboxType.Ensure'
      With = @{
        Provider    = 'ExchangeOnline'
        IdentityKey = 'user@contoso.com'
        Type        = 'Shared'
        # AuthSessionName is optional; defaults to the provider alias if omitted
        # AuthSessionOptions = @{ ... }
      }
    }
  )
}
```

---

## Limitations and known issues

- Requires the `ExchangeOnlineManagement` PowerShell module at runtime.
- The host must establish or broker a usable Exchange Online session; the provider does not connect interactively.

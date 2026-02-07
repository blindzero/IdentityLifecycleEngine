---
title: Provider Reference - IdLE.Provider.Mock
sidebar_label: Mock
---

> **Purpose:** This page is a **reference** for a specific provider implementation.
> Keep it factual and contract-oriented. Put conceptual explanations elsewhere and link to them.

---

## Summary

- **Provider name:** MockIdentity
- **Module:** `IdLE.Provider.Mock`
- **Provider kind:** Identity + Entitlement
- **Targets:** In-memory store (tests/demos)
- **Status:** First-party (bundled)
- **Since:** 0.9.0
- **Compatibility:** PowerShell 7+ (IdLE requirement)

---

## What this provider does

- **Primary responsibilities:**
  - Provide deterministic, in-memory identity operations for tests and examples.
  - Converge identity attributes.
  - List, grant and revoke entitlements (in-memory).
  - Avoid any external dependencies and avoid global state.
- **Out of scope / non-goals:**
  - Any live system integration.
  - Authentication and session handling.

---

## Contracts and capabilities

### Contracts implemented

| Contract | Used by steps for | Notes |
| --- | --- | --- |
| Identity provider (implicit) | Read identities and ensure attributes | Creates missing identities on demand to keep demos frictionless. |
| Entitlement provider (implicit) | List/grant/revoke entitlements | Entitlements are normalized to `{ Kind; Id; DisplayName? }` and compared case-insensitively by `Id`. |

### Capability advertisement (`GetCapabilities()`)

- **Implements `GetCapabilities()`**: Yes
- **Capabilities returned (stable identifiers):**
  - `IdLE.Identity.Read`
  - `IdLE.Identity.Attribute.Ensure`
  - `IdLE.Identity.Disable`
  - `IdLE.Entitlement.List`
  - `IdLE.Entitlement.Grant`
  - `IdLE.Entitlement.Revoke`

---

## Authentication and session acquisition

This provider does not require authentication.

- **AuthSessionType usage:** Not applicable

The Mock provider does not acquire or require auth sessions. You do not need to configure an `AuthSessionBroker` when using this provider. If a broker is supplied for broader test scaffolding, this provider will ignore any acquired auth session.

:::warning

**Security notes**

- Even in tests, do not embed real secrets into workflow files or fixtures.

:::

### Auth examples

This provider does not require authentication.

```powershell
$providers = @{
  Identity = New-IdleMockIdentityProvider
}
```

---

## Configuration

### Provider constructor / factory

- **Public constructor cmdlet(s):**
  - `New-IdleMockIdentityProvider` — creates an isolated in-memory provider instance.

**Parameters (high signal only)**

- `-InitialStore <hashtable>` — optional initial content, shallow-copied into the provider store.

### Provider bag / alias usage

```powershell
$provider = New-IdleMockIdentityProvider

$providers = @{
  Identity = $provider
}
```

- **Recommended alias pattern:** `Identity`
- **Default alias expected by built-in steps (if any):** `Identity`

---

## Provider-specific options reference

This provider has no additional data-only option keys beyond its constructor parameters.

---

## Operational behavior

### Idempotency and consistency

- **Idempotent operations:** Partial
  - `EnsureAttribute` is idempotent (returns `Changed = $false` when already converged).
  - `DisableIdentity` is idempotent.
  - Entitlement grant/revoke are idempotent by Kind+Id.
  - `GetIdentity` creates missing identities on demand (test convenience).
- **Consistency model:** Strong (in-memory)
- **Concurrency notes:** Not designed for concurrent mutation across threads/runspaces.

### Error mapping and retry behavior

- **Common error categories:** input validation errors (e.g., missing entitlement id)
- **Retry strategy:** none (deterministic, in-memory)

---

## Observability

- **Events emitted by provider (if any):** none
- **Sensitive data redaction:** not applicable (no auth material handled)

---

## Examples

### Minimal host usage

```powershell
# 1) Create provider instance
$provider = New-IdleMockIdentityProvider

# 2) Build provider map
$providers = @{ Identity = $provider }

# 3) Plan + execute
$plan = New-IdlePlan -WorkflowPath <path> -Request <request> -Providers $providers
$result = Invoke-IdlePlan -Plan $plan -Providers $providers
```

### Example workflow snippet

```powershell
@{
  Steps = @(
    @{
      Name = 'Ensure department'
      Type = 'IdLE.Step.EnsureAttribute'
      With = @{
        Provider    = 'Identity'
        IdentityKey = 'user1'
        Name        = 'Department'
        Value       = 'IT'
      }
    }
  )
}
```

---

## Limitations and known issues

- Designed for tests and examples only.
- `GetIdentity` auto-creates missing identities, which may hide "NotFound" scenarios unless tests seed the store explicitly.

# Provider Reference Template

> **Purpose:** This page is a **reference** for a specific provider implementation.
> Keep it factual and contract-oriented. Put conceptual explanations elsewhere and link to them.

---

## Summary

- **Provider name:** `<ProviderName>`
- **Module:** `<ModuleName>` (e.g. `IdLE.Provider.*`)
- **Provider kind:** `<Identity | Entitlement | Messaging | Other>`
- **Targets:** `<e.g. Active Directory, Entra ID, REST API>`
- **Status:** `<Built-in | First-party | Community | Experimental>`
- **Since:** `<Version>` (optional)
- **Compatibility:** PowerShell 7+ (IdLE requirement)

---

## What this provider does

- **Primary responsibilities:**  
  - `<bullet>`
  - `<bullet>`
- **Out of scope / non-goals:**  
  - `<bullet>`
  - `<bullet>`

---

## Contracts and capabilities

### Contracts implemented

List the IdLE provider contracts this provider implements and what they mean at a glance.

| Contract | Used by steps for | Notes |
| --- | --- | --- |
| `<IIdleIdentityProvider>` | `<identity read/write>` | `<notes>` |
| `<IIdleEntitlementProvider>` | `<grant/revoke/list entitlements>` | `<notes>` |

> Keep the contract list stable and link to the canonical contract reference.

### Capability advertisement (`GetCapabilities()`)

- **Implements `GetCapabilities()`**: `<Yes/No>`
- **Capabilities returned (stable identifiers):**
  - `<IdLE.Identity.Read>`
  - `<IdLE.Identity.Attribute.Ensure>`
  - `<IdLE.Entitlement.List>`

---

## Authentication and session acquisition

> Providers must not prompt for auth. Use the host-provided broker contract.

- **Auth session name(s) requested via `Context.AcquireAuthSession(...)`:**
  - `<MicrosoftGraph | ActiveDirectory | ExchangeOnline | ...>`
- **Session options (data-only):**
  - `<Key>`: `<Type>` — `<Meaning>` (optional default: `<...>`)

:::warn

**Security notes**

- Do not pass secrets in provider options.
- Ensure token/credential objects are not emitted in events.

:::

---

## Configuration

### Provider constructor / factory

How to create an instance.

- **Public constructor cmdlet(s):**  
  - `<New-IdleXxxProvider>` — `<short purpose>`

**Parameters (high signal only)**

- `-Name <string>` — `<...>`
- `-Options <hashtable>` — `<...>`

> Do not copy full comment-based help here. Link to the cmdlet reference.

### Provider bag / alias usage

How to pass the provider instance to IdLE as part of the host's provider map.

```powershell
$providers = @{
  <AliasName> = <ProviderInstance>
}
```

- **Recommended alias pattern:** `<Identity | Entitlement | SourceAD | TargetEntra | ...>`
- **Default alias expected by built-in steps (if any):** `<Identity>` (if applicable)

---

## Provider-specific options reference

> Document only **data-only** keys. Keep this list short and unambiguous.

| Option key | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `<OptionA>` | `<string>` | `<Yes/No>` | `<...>` | `<...>` |
| `<OptionB>` | `<int>` | `<Yes/No>` | `<...>` | `<...>` |

---

## Operational behavior

### Idempotency and consistency

- **Idempotent operations:** `<Yes/No/Partial>`
- **Consistency model:** `<Strong/Eventually consistent/Depends on target>`
- **Concurrency notes:** `<locking, retries, throttling>`

### Error mapping and retry behavior

- **Common error categories:** `<NotFound, AlreadyExists, PermissionDenied, Throttled>`
- **Retry strategy:** `<none | exponential backoff | delegated to host>`

---

## Observability

- **Events emitted by provider (if any):**  
  - `<Type>` — `<When>` — `<Data keys>`
- **Sensitive data redaction:** `<how/where ensured>`

---

## Examples

### Minimal host usage

```powershell
# 1) Create provider instance
$provider = <New-IdleXxxProvider ...>

# 2) Build provider map
$providers = @{ <Alias> = $provider }

# 3) Plan + execute
$plan = New-IdlePlan -WorkflowPath <path> -Request <request> -Providers $providers
$result = Invoke-IdlePlan -Plan $plan -Providers $providers
```

### Example workflow snippet

```powershell
@{
  Steps = @(
    @{
      Name = '<Step name>'
      Type = '<IdLE.Step.Whatever>'
      With = @{
        Provider = '<Alias>'
        # ...
      }
    }
  )
}
```

---

## Limitations and known issues

- `<bullet>`
- `<bullet>`

---

## Testing

- **Unit tests:** `<path(s)>`
- **Contract tests:** `<path(s)>`
- **Known CI constraints:** `<e.g. no live system calls>`

---

## Changelog (optional)

- `<Version>` — `<Notable change>`

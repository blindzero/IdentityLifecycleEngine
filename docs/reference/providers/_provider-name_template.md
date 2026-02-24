# Provider Reference Template

> **Audience:** Admins and workflow authors (not developers).  
> **Goal:** Help users get the provider running, wire authentication, understand what steps it supports, and copy working examples.
>
> Keep the page **practical** and **scan-friendly**:
> - Prefer short tables over long prose.
> - Avoid implementation details (interfaces, contracts, test paths, CI notes).
> - Do not document "from source" installation here.

---

## Summary

| Item | Value |
| --- | --- |
| **Provider name** | `<ProviderName>` |
| **Module** | `<ModuleName>` (e.g. `IdLE.Provider.*`) |
| **Provider role** | `<Identity | Entitlement | Messaging | DirectorySync | Other>` |
| **Targets** | `<e.g. Active Directory, Entra ID, Exchange Online, REST API>` |
| **Status** | `<Built-in | First-party | Community | Experimental>` |
| **Since** | `<Version>` (optional) |
| **PowerShell** | PowerShell 7+ |

---

## When to use this provider

### Use cases

- `<bullet>`
- `<bullet>`

### Out of scope

- `<bullet>`
- `<bullet>`

---

## Getting started

### Requirements

> List only what an admin must prepare **before** installing.

- **Dependencies:** `<RSAT / module names / OS requirements>`
- **Permissions / roles:** `<minimal required roles/scopes>`
- **Network / endpoints:** `<URLs / ports / proxies>` (if applicable)

### Install (PowerShell Gallery)

```powershell
Install-Module <ModuleName> -Scope CurrentUser
```

> Optional: add `-RequiredVersion` or `Update-Module` notes if needed.

### Import & basic check

```powershell
Import-Module <ModuleName>

# Create provider instance (minimal)
$provider = <New-IdleXxxProvider ...>
```

If import or creation fails, see **Troubleshooting**.

---

## Quickstart (minimal runnable)

> Provide the smallest, realistic end-to-end example (copy/paste).

```powershell
# 1) Provider instance
$provider = <New-IdleXxxProvider ...>

# 2) Provider map (alias used in workflows)
$providers = @{
  <AliasName> = $provider
}

# 3) Plan + execute (example shape)
$plan   = New-IdlePlan -WorkflowPath <path> -Request <request> -Providers $providers
$result = Invoke-IdlePlan -Plan $plan -Providers $providers
```

---

## Authentication

> Providers must not prompt for auth. They acquire sessions via the host's AuthSessionBroker.

- **Auth session type(s):** `<e.g. MicrosoftGraph | ActiveDirectory | ExchangeOnline | ...>`
- **Auth session name(s):** `<e.g. Graph | AD | EXO | ...>` (if multiple, list when/why)
- **Session options (data-only):**
  - `<Key>`: `<Type>` — `<Meaning>` (default: `<...>`)

:::warning
**Security**
- Do not pass secrets in provider options or workflow files.
- Ensure credentials/tokens are not written to logs or events.
:::

---

## Supported step types

> Admins think in **Step Types**. List what works with this provider.

| Step Type | Capability Required | Typical use |
| --- | --- | --- |
| `<IdLE.Step.X>` | `<IdLE.Capability.Name>` | `<What an admin achieves>` |
| `<IdLE.Step.Y>` | `<...>` | `<...>` |

### Step inputs (With.*)

> For each step type, document the `With` keys an admin needs to configure.
> Columns: Key | Type | Required | Default | Description.

**`<IdLE.Step.X>`**

| Key | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `IdentityKey` | `string` | Yes | — | UPN, SMTP address, or identity key. Supports `{{Request.*}}` template expressions. |
| `<StepKey>` | `<type>` | `<Yes/No>` | `<...>` | `<...>` |
| `Provider` | `string` | No | `<DefaultAlias>` | Provider alias key in the providers map. |
| `AuthSessionName` | `string` | No | `Provider` value | Auth session name passed to `Context.AcquireAuthSession()`. |
| `AuthSessionOptions` | `hashtable` | No | `$null` | Data-only options for the auth session broker (e.g., `@{ Role = 'Admin' }`). |

> See the [step reference pages](../steps.md) for the full `With.*` schema for each step type.

---

## Configuration

### Provider creation

- **Factory cmdlet(s):**
  - `<New-IdleXxxProvider>` — `<short purpose>`

**High-signal parameters (only)**

- `-Name <string>` — `<...>`
- `-Options <hashtable>` — `<...>`

> Link to cmdlet reference instead of copying full help.

### Provider alias usage

```powershell
$providers = @{
  <AliasName> = <ProviderInstance>
}
```

- **Recommended alias:** `<Identity | Entitlement | SourceAD | TargetEntra | ...>`
- **Default alias expected by built-in steps (if any):** `<Identity>` (optional)

### Options reference

> Document only **data-only** keys. Keep this list short and unambiguous.

| Option key | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `<OptionA>` | `<string>` | `<Yes/No>` | `<...>` | `<...>` |
| `<OptionB>` | `<int>` | `<Yes/No>` | `<...>` | `<...>` |

---

## Operational behavior

- **Idempotency:** `<Yes/No/Partial>` — `<What happens on re-run>`
- **Consistency model:** `<Strong/Eventually consistent/Depends>`
- **Throttling / rate limits:** `<What admins should expect>`
- **Retry behavior:** `<none | built-in | delegated to host>`

---

## Examples

> Keep only 1–2 short examples inline. Link to the repository's `examples/` for more.
> Show complete `With` blocks including all required and commonly used optional keys.

### Example workflow (template)

```powershell
@{
  Steps = @(
    @{
      Name = '<Step name>'
      Type = '<IdLE.Step.Whatever>'
      With = @{
        Provider           = '<AliasName>'
        IdentityKey        = '{{Request.Intent.UserPrincipalName}}'
        # Step-specific required keys:
        <Key>              = '<value>'
        # Optional auth override (omit to use Provider value as session name):
        # AuthSessionName    = '<SessionName>'
        # AuthSessionOptions = @{ Role = 'Admin' }
      }
    }
  )
}
```

### More examples

- `<Link to an examples page / list>`  
- `<Link to specific example files>`

> Documentation author note: if your site uses MDX, you can embed `.psd1` examples directly from `/examples` to avoid duplication.

---

## Troubleshooting

> Keep this practical and symptom-driven.

### Common problems

- **Import fails:** `<Likely cause>` → `<Fix>`
- **Auth session not found:** `<Likely cause>` → `<Fix>`
- **Permission denied:** `<Likely cause>` → `<Fix>`
- **Step fails due to provider mismatch:** `<Likely cause>` → `<Fix>`

### What to collect for support

- IdLE version, provider module version
- Redacted error message / event id
- Target system region/tenant (if relevant), without secrets

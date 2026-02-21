---
title: Walkthrough 5 - Providers and authentication
sidebar_label: "5. Providers and authentication"
---

# Walkthrough 5: Providers and authentication

This page completes the end-to-end IdLE lifecycle walkthrough:

**Workflow → Request → Plan → Invoke → Providers/Auth**

Providers and authentication are **host responsibilities**. Workflows and requests remain **data-only**.

---

## Goal

- Understand how workflow steps reference providers by alias (`With.Provider`)
- Understand how steps acquire authentication sessions at runtime (optional)
- Build a provider registry that works for both plan build and execution

## You will have

- A provider registry hashtable that contains:
  - at least one system provider (for example: `Identity`)
  - optionally an `AuthSessionBroker` for runtime credential selection

---

## 1) Provider mapping (alias → provider instance)

IdLE expects a hashtable of providers keyed by **alias**. Steps reference the alias via `With.Provider`.

Example host mapping (mock provider):

```powershell
Import-Module -Name IdLE.Provider.Mock

$providers = @{
  Identity = New-IdleMockIdentityProvider
}
```

Example workflow usage:

```powershell
@{
  Name = 'Ensure demo attributes'
  Type = 'IdLE.Step.EnsureAttributes'
  With = @{
    Provider    = 'Identity'
    IdentityKey = '{{Request.IdentityKeys.EmployeeId}}'
    Attributes  = @{
      GivenName = '{{Request.DesiredState.GivenName}}'
      Surname   = '{{Request.DesiredState.Surname}}'
    }
  }
}
```

:::info
If `With.Provider` is omitted, many provider-agnostic steps default to the alias `'Identity'`.
:::

---

## 2) When to supply providers

### Recommended: supply providers during plan build

This enables **fail-fast** validation (missing provider aliases, missing capabilities).

```powershell
$plan = New-IdlePlan -WorkflowPath ./joiner.psd1 -Request $request -Providers $providers
$result = Invoke-IdlePlan -Plan $plan
```

### Alternative: supply providers at invoke time

This is useful for exported plans or environment-specific overrides.

```powershell
$plan = New-IdlePlan -WorkflowPath ./joiner.psd1 -Request $request
$result = Invoke-IdlePlan -Plan $plan -Providers $providers
```

---

## 3) Authentication is optional, but always host-owned

IdLE workflows **must not** contain secrets.

If a step needs credentials at runtime, it can request an auth session via:

- `With.AuthSessionName` (string)
- `With.AuthSessionOptions` (optional hashtable)

Example (step requests a named session):

```powershell
@{
  Name = 'Ensure AD attributes (example)'
  Type = 'IdLE.Step.EnsureAttributes'
  With = @{
    Provider           = 'Identity'
    AuthSessionName    = 'AD'
    AuthSessionOptions = @{ Role = 'Tier0' }

    IdentityKey = '{{Request.IdentityKeys.EmployeeId}}'
    Attributes  = @{
      Department = '{{Request.DesiredState.Department}}'
    }
  }
}
```

During execution, the step will call `Context.AcquireAuthSession(AuthSessionName, AuthSessionOptions)` and pass the returned session to the provider method (if the provider supports an `AuthSession` parameter).

:::warning
ScriptBlocks in `AuthSessionOptions` are rejected. Keep auth options **data-only**.
:::

---

## 4) Configure an AuthSessionBroker (simple pattern)

IdLE supports a simple, host-owned broker that routes sessions based on options.

A minimal broker for a single credential:

```powershell
$cred = Get-Credential

$authSessionBroker = New-IdleAuthSession -DefaultAuthSession $cred -AuthSessionType 'Credential'
```

A broker that supports named routing (example: `AD` and `EXO`):

```powershell
$adCred  = Get-Credential
$exoToken = '<token-or-object-from-your-exo-login-flow>'

$authSessionBroker = New-IdleAuthSession -SessionMap @{
  @{ AuthSessionName = 'AD' }  = @{ AuthSessionType = 'Credential'; Credential = $adCred }
  @{ AuthSessionName = 'EXO' } = @{ AuthSessionType = 'OAuth';       Credential = $exoToken }
}
```

:::info Framework-Reserved Keys

The execution framework automatically injects `CorrelationId` and `Actor` into auth session options during execution. These keys have special handling:

- **AuthSessionName-only patterns** (e.g., `@{ AuthSessionName = 'AD' }`): Framework keys are ignored during matching, allowing simple patterns to work regardless of injected metadata
- **Multi-key patterns** (e.g., `@{ AuthSessionName = 'AD'; Actor = 'ops-user' }`): Framework keys participate in matching, enabling advanced actor-based routing

**Recommendation**: Use user-defined routing keys (like `Role`, `Environment`, `Tier`) instead of `Actor` or `CorrelationId` to avoid confusion, as framework values change per execution and are not under user control.
:::

To make the broker available at runtime, add it to the provider registry under the key `AuthSessionBroker`:

```powershell
$providers = @{
  Identity         = New-IdleMockIdentityProvider
  AuthSessionBroker = $authSessionBroker
}
```

:::info
Providers can also work without a broker (for example: integrated authentication / run-as credentials).
The broker is the recommended mechanism when you need runtime selection without embedding secrets.
:::


---

## Reference

- Provider contracts, capability model, and provider-specific authentication: [Reference: Providers](../../reference/providers.md)
- Workflow field details, templates, conditions: [Reference: Steps](../../reference/steps.md)

---

## You are done (walkthrough)

You now have the full end-to-end flow:

1. Workflow definition (`.psd1`)
2. Request object
3. Plan build (fail-fast)
4. Invoke and inspect results/events
5. Providers & (optional) authentication

Next, consider using **[Plan Export](../plan-export.md)** for review/approval and CI artifacts.

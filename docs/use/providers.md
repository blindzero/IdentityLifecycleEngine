---
title: Providers
sidebar_label: Providers
---

Providers are **system-specific adapters** (for example: Active Directory, Entra ID, Exchange Online) that connect IdLE steps to external systems.

In IdLE, providers are **supplied by your host** (script, CI job, service). Workflows and requests remain **data-only**.

:::info
**Reference-first:** Provider contracts, authentication models, and provider-specific details live in the Reference section.
This page explains how providers are used in the **lifecycle flow** (plan build and execution) without duplicating reference content.
:::

---

## What providers do

A provider typically:

- translates generic IdLE **operations to a system API**
- **exposes capabilities** used during plan validation
- **uses an AuthSessionBroker** (or equivalent host-provided authentication) to access systems
- supports mocking for tests

See the big-picture responsibility model in [Concepts](../about/concepts.md#responsibilities).

---

## Provider mapping (alias → provider instance)

IdLE expects a hashtable of providers keyed by **alias**.

The alias is what workflow steps reference via `With.Provider`.

```powershell
Import-Module -Name IdLE.Provider.Mock

$providers = @{
  Identity = New-IdleMockIdentityProvider
}
```

:::tip
You can use any provider alias, it is just a string used as a reference.
:::

In your workflow, a step references that alias:

```powershell
@{
  Name = 'Ensure demo attributes'
  Type = 'IdLE.Step.EnsureAttributes'
  With = @{
    Provider = 'Identity'
    # ...
  }
}
```

---

## When providers are supplied

There are two supported patterns:

### 1) Supply providers during plan build (recommended)

This enables **fail-fast** validation (capabilities, required provider presence) at plan-build time.

```powershell
$plan = New-IdlePlan -WorkflowPath ./joiner.psd1 -Request $request -Providers $providers
$result = Invoke-IdlePlan -Plan $plan
```

### 2) Supply providers at execution time (overrides / exported plans)

This is useful when:

- you execute a plan that was exported and approved elsewhere
- you need environment-specific provider instances (dev/test/prod)
- you want to override a provider mapping for one run

```powershell
$plan = New-IdlePlan -WorkflowPath ./joiner.psd1 -Request $request

$result = Invoke-IdlePlan -Plan $plan -Providers $providers
```

For exported plans, see [Plan Export](./plan-export).

---

## Authentication (host responsibility)

IdLE workflows **shall not** contain secrets.

Authentication is provided by your host, typically via an **AuthSessionBroker** (or another host-managed mechanism), and then used by providers and/or steps.

At a high level, the host is responsible for:

- choosing the auth mechanism (token, certificate, managed identity, workload identity, etc.)
- acquiring and caching sessions as needed
- injecting the broker or session factory into provider instances

Generic example (host-managed auth, provider-agnostic):

```powershell
# A step can request an auth session by name and optional options.
$workflowStep = @{
  Name = 'Ensure attributes (example)'
  Type = 'IdLE.Step.EnsureAttributes'
  With = @{
    Provider           = 'Identity'
    AuthSessionName    = 'AD'
    AuthSessionOptions = @{ Role = 'Tier0' }

    IdentityKey = '{{Request.IdentityKeys.EmployeeId}}'
    Attributes  = @{ Department = '{{Request.Intent.Department}}' }
  }
}

# Host configures a broker and supplies it alongside providers.
$adCred   = Get-Credential
$exoToken = '<token-or-object-from-your-exo-login-flow>'

$authSessionBroker = New-IdleAuthSession -SessionMap @{
  @{ AuthSessionName = 'AD' }  = @{ AuthSessionType = 'Credential'; Credential = $adCred }
  @{ AuthSessionName = 'EXO' } = @{ AuthSessionType = 'OAuth';       Credential = $exoToken }
}

$providers = @{
  Identity          = New-IdleMockIdentityProvider
  AuthSessionBroker = $authSessionBroker
}

$plan = New-IdlePlan -WorkflowPath ./joiner.psd1 -Request $request -Providers $providers
Invoke-IdlePlan -Plan $plan
```

During execution, the step will call `Context.AcquireAuthSession(AuthSessionName, AuthSessionOptions)` and pass the returned `AuthSession` to the provider method (if the provider supports an `AuthSession` parameter).

:::warning
Do not store credentials, tokens, or executable ScriptBlocks in workflow files.
Keep workflows and requests **data-only**.
:::

Provider-specific authentication variants and required options are documented in the provider reference. For authentication patterns and provider contracts, see:

- [Reference: Providers](../reference/providers.md)

---

## Next steps

- If you have not done so yet, start with the [Quick Start](quickstart.md).
- For the full end-to-end flow, follow the [Walkthrough](walkthrough/01-workflow-definition.md).
- For full specifications and examples, use the [Reference](../reference/intro-reference.md) section.

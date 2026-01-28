---
title: Providers
sidebar_label: Providers
---

# Providers and Contracts

## Purpose

Providers in IdLE are responsible for interacting with external systems such as
identity stores, directories, or resource systems. They form the boundary between
the IdLE core engine and the outside world.

This document explains the conceptual role of providers, what is meant by
"contracts" in IdLE, and how responsibilities are intentionally separated to keep
the engine portable, testable, and host-agnostic.

---

## Concept

### Providers as infrastructure adapters

A provider is an **adapter to an external system**.

Examples include:

- identity directories (Active Directory, Entra ID)
- account stores
- entitlement systems
- mock or file-based systems used for testing

The IdLE core engine does not know *how* a provider works.
It only knows **what it expects from it**.

This allows the same workflow and plan to run:

- locally with mock providers
- in CI pipelines
- in production environments

without modification.

---

### What is a contract?

In IdLE, a contract is **not a formal interface or class**.

A contract is a **shared expectation** between:

- the engine
- steps
- providers

It defines:

- which capabilities are required
- which inputs are expected
- which outputs are returned
- how errors are represented

Contracts are intentionally **implicit and lightweight**, following PowerShell
conventions rather than strict type systems.

---

### Why contracts are implicit

IdLE favors implicit contracts because they:

- align with PowerShell's object-based pipeline model
- avoid rigid inheritance hierarchies
- keep providers easy to mock and test
- allow gradual evolution without breaking existing implementations

The contract is expressed through:

- documented behavior
- expected object shapes
- consistent naming and semantics

---

## Responsibilities

### Separation of responsibilities

Clear separation is essential for maintainability:

- **Engine**
  - Orchestrates workflow execution
  - Invokes steps
  - Passes providers to steps
  - Never depends on provider internals

- **Steps**
  - Implement domain logic
  - Use providers through contracts
  - Must not assume a specific provider implementation

- **Providers**
  - Implement infrastructure-specific behavior
  - Fulfill contracts expected by steps
  - Encapsulate external system details
  - Authenticate and manage sessions
  - Translate generic operations to system APIs
  - Are mockable for tests
  - Avoid global state

- **Host**
  - Selects and configures providers
  - Injects providers into plan execution
  - Decides which provider implementations are used

This separation keeps the core engine free of environmental assumptions.

**Important:** Steps should not handle authentication. Authentication is a provider responsibility via AuthSessionBroker.

---

## Usage

### Provider Aliases

When you supply providers to IdLE, you use a **hashtable** that maps **alias names** to **provider instances**:

```powershell
$providers = @{
    Identity = $adProvider
}
```

#### Alias Naming

The alias name (hashtable key) is **completely flexible** and chosen by you (the host):

- It can be any valid PowerShell hashtable key
- Common patterns:
  - **Role-based**: `Identity`, `Entitlement`, `Messaging` (when you have one provider per role)
  - **Instance-based**: `SourceAD`, `TargetEntra`, `ProdForest`, `DevSystem` (when you have multiple providers)
- The built-in steps default to `'Identity'` if no `Provider` is specified in the step's `With` block

#### How Workflows Reference Providers

Workflow steps can specify which provider to use via the `Provider` key in the `With` block:

```powershell
@{
    Name = 'Create user in source'
    Type = 'IdLE.Step.CreateIdentity'
    With = @{
        IdentityKey = 'newuser'
        Attributes  = @{ ... }
        Provider    = 'SourceAD'  # References the alias from the provider hashtable
    }
}
```

If `Provider` is not specified, it defaults to `'Identity'`:

```powershell
# These are equivalent when Provider is not specified:
With = @{ IdentityKey = 'user1'; Name = 'Department'; Value = 'IT' }
With = @{ IdentityKey = 'user1'; Name = 'Department'; Value = 'IT'; Provider = 'Identity' }
```

#### Multiple Provider Example

```powershell
# Create provider instances
$sourceAD = New-IdleADIdentityProvider -Credential $sourceCred
$targetEntra = New-IdleEntraIDIdentityProvider -Credential $targetCred

# Map to custom aliases
$providers = @{
    SourceAD    = $sourceAD
    TargetEntra = $targetEntra
}

# Workflow steps reference the aliases
# Step 1: With = @{ Provider = 'SourceAD'; ... }
# Step 2: With = @{ Provider = 'TargetEntra'; ... }
```

---

### Provider Categories

While IdLE does not enforce provider categories, common conceptual groupings exist:

- **Identity providers**
  - Manage identities, attributes, and lifecycle state

- **Resource or entitlement providers**
  - Manage group membership, permissions, or access rights

- **Mock and test providers**
  - Used for unit tests and demos
  - Provide deterministic, side-effect-free behavior

These categories are descriptive, not prescriptive.

---

### Provider injection

Providers are supplied by the host at execution time.

This enables:

- swapping implementations without changing workflows
- testing workflows with mock providers
- running the same plan in different environments

The engine treats providers as opaque objects and does not validate
their implementation beyond contract usage.

---

## Auth session acquisition (AuthSessionBroker)

Many providers require authenticated connections (tokens, API clients, remote sessions).
IdLE keeps authentication out of the engine and out of individual providers by using a
host-supplied broker.

### Contract

The host injects an **AuthSessionBroker** into the providers map:

- `Providers.AuthSessionBroker`

During execution, steps and providers may acquire sessions via the execution context:

- `Context.AcquireAuthSession(Name, Options)`

Where:

- `Name` identifies the requested session (e.g. `Graph`, `ExchangeOnline`, `Ldap`, ...).
- `Options` is an optional **data-only** hashtable.
  - `$null` is treated as an empty hashtable.
  - ScriptBlocks are rejected, including nested values.

The broker must expose a method:

- `AcquireAuthSession(Name, Options)`

### Responsibility boundaries

- **Engine**
  - Provides `Context.AcquireAuthSession()` as a stable API.
  - Enforces the data-only boundary for `Options`.
  - Does not implement authentication.

- **Host**
  - Implements and configures the AuthSessionBroker.
  - Decides how to authenticate (interactive, managed identity, certificate, secrets, ...).
  - Must ensure secrets are not leaked into plans, events, or exports.

- **Providers / Steps**
  - Request sessions through the execution context.
  - Must not perform their own authentication flows.

### Enrichment

The execution context may enrich the broker request with common run metadata, such as:

- `CorrelationId`
- `Actor`

Providers and steps should treat these values as optional.

---

## Execution context injection (backwards compatibility)

IdLE step handlers can optionally accept a `Context` parameter.

To remain backwards compatible, the engine passes `-Context $Context` **only if** the
handler supports a `Context` parameter.

Guidance:

- New step handlers should accept `Context` to access providers, event sink, and auth session acquisition.
- Existing handlers without `Context` continue to work unchanged.

---

## Testing providers

Providers should have contract tests that verify behavior against a mock or test harness.
Unit tests must not call live systems.

For testing guidance, see [Testing](../develop/testing.md).

---

## Trust and security

Providers and the step registry are host-controlled extension points and should be treated as trusted code.
Workflows and lifecycle requests are data-only and must not contain executable objects.

For details, see [Security](../about/security.md).

---

## Common pitfalls

### Treating providers as part of the engine

Providers must not be embedded into the core engine or steps.

Doing so would:

- break portability
- reduce testability
- tightly couple IdLE to specific environments

---

### Over-formalizing contracts

Introducing strict interfaces or class hierarchies for providers can
quickly make implementations brittle.

Contracts should remain:

- behavior-focused
- documented
- enforced by tests and usage patterns

---

### Assuming a specific provider implementation

Steps must never rely on provider-specific behavior beyond the documented contract.

If a step requires provider-specific functionality, the contract itself
should be clarified or refined.

---

## Related documentation

- [Workflows](../use/workflows.md)
- [Steps](../use/steps.md)
- [Architecture](../about/architecture.md)
- [Extensibility](../extend/extensibility.md)
- [Capabilities](../reference/capabilities.md)

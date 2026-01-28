---
title: Extensibility
sidebar_label: Extensibility
---

# Extensibility

IdLE is designed for change through modules instead of forks.

---

## Add a new step

A new step typically involves:

1. A metadata definition (what inputs and outputs are allowed)
2. A planning function (test) that produces data-only actions
3. An execution function (invoke) that performs actions via providers
4. Unit tests (Pester)

Steps can emit structured events using the execution context contract:

- `Context.EventSink.WriteEvent(Type, Message, StepName, Data)`

Keep steps host-agnostic: do not call UI APIs directly.

---

## Add a new provider

Providers are responsible for interacting with external systems (directories,
cloud services, APIs, etc.).

A new provider typically involves:

1. A contract interface (if not already present)
2. A provider implementation module
3. Auth session acquisition via host execution context (AuthSessionBroker)
4. Contract tests and unit tests

### Auth session acquisition

IdLE keeps authentication out of the core engine. Providers acquire sessions through the execution context:

- `Context.AcquireAuthSession(Name, Options)`

Key points:

- Hosts provide an AuthSessionBroker via `Providers.AuthSessionBroker`
- Providers request sessions by name (e.g., `MicrosoftGraph`, `ActiveDirectory`)
- Options are data-only (ScriptBlocks rejected)
- The broker handles caching, interactive auth policy, and secret management

For detailed contract specifications and usage patterns, see:

**→ [Providers and Contracts](../extend/providers.md)** — Complete provider contracts and AuthSessionBroker details

### Capability Advertisement

Providers must explicitly advertise their supported capabilities via a
`GetCapabilities()` method. These capabilities are used by the engine
during plan build to validate whether all required functionality is
available.

The full contract, naming rules, and validation behavior are described in
[Provider Capabilities](../reference/capabilities.md).

Providers should include the corresponding provider capability contract tests
to ensure compliance.

---

## Versioning strategy

Keep workflows stable by treating step identifiers as contracts.
If behavior changes incompatibly:

- introduce a new step id or explicit handler mapping
- keep the old step id available for older workflows

---

## Keep the core headless

Do not add:

- interactive prompts
- authentication code inside steps
- authentication flows inside providers (use AuthSessionBroker)
- UI or web server dependencies

Those belong in a host application.

---

## Register step handlers

Steps are executed via a host-provided step registry.

- Workflows reference steps by `Type` (identifier).
- The host maps this identifier to a **function name** (string) in the step registry.

ScriptBlock handlers are intentionally not supported as a secure default.

Step handlers may optionally declare a `Context` parameter.
For backwards compatibility, the engine passes `-Context` only when the handler
supports it.

---

## Related

- [Providers and Contracts](../extend/providers.md) — Provider extension guidance
- [Provider Capabilities](../reference/capabilities.md) — Capability system
- [Architecture](../about/architecture.md) — Design principles

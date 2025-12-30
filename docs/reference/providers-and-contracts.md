# Providers and Contracts

## Purpose

Providers in IdLE are responsible for interacting with external systems such as
identity stores, directories, or resource systems. They form the boundary between
the IdLE core engine and the outside world.

This document explains the conceptual role of providers, what is meant by
"contracts" in IdLE, and how responsibilities are intentionally separated to keep
the engine portable, testable, and host-agnostic.

---

## Scope

This document covers:

- The role of providers in IdLE
- The meaning of contracts and why they exist
- Responsibility boundaries between engine, steps, providers, and host
- Conceptual provider categories
- Recommended usage patterns

Out of scope:

- Detailed API or method reference
- Provider configuration schema
- Step-specific provider requirements
- Implementation details of concrete providers

---

## Concept

### Providers as infrastructure adapters

A provider is an **adapter to an external system**.

Examples include:

- identity directories
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

- align with PowerShell’s object-based pipeline model
- avoid rigid inheritance hierarchies
- keep providers easy to mock and test
- allow gradual evolution without breaking existing implementations

The contract is expressed through:

- documented behavior
- expected object shapes
- consistent naming and semantics

---

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

- **Host**
  - Selects and configures providers
  - Injects providers into plan execution
  - Decides which provider implementations are used

This separation keeps the core engine free of environmental assumptions.

---

## Usage

### Typical provider categories

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

- [Steps](../usage/steps.md)
- [Providers](../usage/providers.md)
- [Workflows](../usage/workflows.md)
- [Architecture](../advanced/architecture.md)

# Overview

IdLE (IdentityLifecycleEngine) is a **generic orchestration framework** for identity lifecycle automation.

The key idea is to **separate intent from implementation**:

- **What** should happen is defined in a **workflow** (data-only configuration).
- **How** it happens is implemented by **steps** and **providers** (pluggable modules).

---

## Why IdLE exists

Identity lifecycle automation often turns into long scripts that are:

- tightly coupled to one environment
- hard to test
- hard to change safely

IdLE aims to be:

- **portable** (PowerShell 7 runs on many platforms)
- **modular** (steps and providers are swappable)
- **testable** (Pester-friendly, mock providers)
- **configuration-driven** (workflows as data)

---

## Key Features

- **Joiner / Mover / Leaver** orchestration (and custom lifecycle events)
- **Plan → Execute** flow (preview actions before applying them)
- **Plugin step model** (`Test` / `Invoke`, optional `Rollback` later)
- **Provider/Adapter pattern** (directory, SaaS, REST, file/mock…)
- **Structured events** for audit/progress (CorrelationId, Actor, step results)
- **Idempotent execution** (steps can be written to converge state)

---

## Core concepts

### Request

A **LifecycleRequest** represents the business intent (for example: Joiner, Mover, Leaver).
It is the input to planning.

### Plan

A **LifecyclePlan** is created deterministically from:

- request
- workflow definition
- step catalog / step registry

The plan is previewable and auditable.

### Execute

Execution runs **only the plan** (no re-planning). This supports:

- approvals
- repeatability
- deterministic audits

---

## Building Blocks

### Steps

**Steps** are reusable plugins that define convergence logic. They:

- Operate idempotently (converge towards desired state)
- Are provider-agnostic (use contracts, not direct system calls)
- Emit structured events for audit and progress

Learn more: [Steps](../usage/steps.md) | [Step Catalog](../reference/steps.md)

### Providers

**Providers** are system-specific adapters that connect workflows to external systems. They:

- Authenticate and manage sessions
- Translate generic operations to system APIs
- Are mockable for tests

Learn more: [Providers](../usage/providers.md) | [Providers and Contracts](../reference/providers-and-contracts.md)

---

## Non-goals (V1)

IdLE.Core stays headless and avoids responsibilities that belong to a host application:

- no UI framework
- no interactive prompts
- no authentication flows inside steps
- no dynamic code execution from configuration

---

## Next Steps

- [Installation](../getting-started/installation.md) — Install and import guide
- [Quickstart](../getting-started/quickstart.md) — Run the demo
- [Architecture](../advanced/architecture.md) — Design principles and decisions
- [Workflows](../usage/workflows.md) — Define lifecycle workflows

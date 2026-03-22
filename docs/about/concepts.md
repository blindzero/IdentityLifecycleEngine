---
title: IdLE Concepts
sidebar_label: Concepts
---

IdLE is a **generic, headless, configuration-driven engine for identity lifecycle automation** (Joiner / Mover / Leaver). It intentionally **separates intent from implementation**:

- **Workflows** (data-only PSD1 files) declare what should happen,
- **Steps** implement provider-agnostic, idempotent convergence logic, and
- **Providers** adapt to external systems and manage authentication.

The engine first builds a **deterministic, auditable execution plan** from a LifecycleRequest and a workflow (Plan → Execute). **Planning validates** conditions, inputs, and required provider capabilities; **Execution runs** only the produced plan to ensure repeatability, safe approvals, and reliable auditing.
This design **prioritizes portability, testability (mockable providers), and minimal runtime assumptions** by keeping the core headless and side-effect free.

This page explains the **big picture**: responsibilities, trust boundaries, and how the core artifacts fit together.

## Start here

- If you want to **run IdLE now**: start with [Quick Start](../use/quickstart.md).
- If you want the **full end-to-end flow**: follow the **Walkthrough**:
  1. [Workflow definition](../use/walkthrough/01-workflow-definition.md)
  2. [Request creation](../use/walkthrough/02-request-creation.md)
  3. [Plan build](../use/walkthrough/03-plan-creation.md)
  4. [Invoke and results](../use/walkthrough/04-invoke-results.md)
  5. [Providers and authentication](../use/walkthrough/05-providers-authentication.md)

## Goals

- **Generic, configurable lifecycle orchestration** (Joiner / Mover / Leaver)
- **Portable, modular, testable**
- **Headless core** (works in CLI, service, CI)
- **Plan-first execution** with structured events

### Non-goals

- No UI framework or service host
- No interactive prompts
- No authentication flows inside steps
- No dynamic code execution from configuration
- No automatic rollback orchestration
- No deep merge semantics for state outputs

---

## Responsibilities

### Separation of Responsibility

**Clear separation of responsibility** is the essential foundation for maintainability:

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

If you want the practical version of this (how to supply providers/auth in a run), see:
[Walkthrough 5: Providers and authentication](../use/walkthrough/05-providers-authentication.md).

---

## Request

A **request represents your business intent** (Joiner/Mover/Leaver) plus the input data required to build a plan.

Typical request content:

- Identity keys (for example: EmployeeId, SamAccountName, UPN)
- Desired state (attributes, entitlements, mailbox settings, …)
- Optional metadata/context

Hands-on: [Walkthrough 2: Request creation](../use/walkthrough/02-request-creation.md).

---

## Workflow

A **workflow is a data-only definition** (`.psd1`) that describes **what** should happen, step by step.

### Workflow Steps

A **workflow consists of ordered steps**. Each step references a **StepType** by name and provides configuration under `With`.

- Hands-on: [Walkthrough 1: Workflow definition](../use/walkthrough/01-workflow-definition.md).
- Specification: [Use → Workflows](../use/workflows.md) and [Reference section](../reference/steps.md).

### Providers

**Workflows reference providers** by alias (for example: `With.Provider = 'Identity'`), but the actual provider instances are supplied by the host. Providers implement step capabilities specifically for each endpoint system.

Hands-on: [Walkthrough 5: Providers and authentication](../use/walkthrough/05-providers-authentication.md).

### Declarative conditions

**Workflows can include declarative conditions** (data-only) to decide whether steps should run.
For details, use the Reference workflow documentation.

---

## Plan

A **plan is the validated, resolved execution contract** produced from a workflow and a request.

Hands-on: [Walkthrough 3: Plan build](../use/walkthrough/03-plan-creation.md).

### Provider Capabilities (Planning-time Validation)

**IdLE validates required capabilities** at plan-build time (fail-fast) against supplied providers.
This prevents discovering missing requirements only at execution time.

### Plan export

**Plans can be exported** as a JSON file for review, approval, CI artifacts, and audit trails.

Hands-on: [Use → Plan Export](../use/plan-export.md).

---

## Execute

Executing a plan **runs the steps in order as planned** and produces a structured result.

Hands-on: [Walkthrough 4: Invoke and results](../use/walkthrough/04-invoke-results.md).

### Eventing

**IdLE emits structured events** during execution.
Your host can log them, forward them, or store them for audit and diagnostics.

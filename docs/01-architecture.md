# IdentityLifecycleEngine (IdLE) - Architecture

## Decisions, Rules, and Rationale

This document captures the **current architecture** of **IdentityLifecycleEngine (IdLE)** and the
**decisions we have made so far**, including the rationale behind them.

---

## 1. Goals and Non-Goals

### Goals

- Provide a **generic**, **configurable** orchestration engine for Identity Lifecycle / JML scenarios.
- Be **portable**, **testable**, and **host-agnostic** (CLI, service, pipeline).
- Prefer **configuration over code** for workflows.
- Support **Plan → Execute** with deterministic execution and strong auditing via events.

### Non-Goals

- No UI framework, web server, or stateful host dependencies inside IdLE.Core.
- No DSL and no dynamic code execution from configuration.
- No automatic rollback orchestration.
- No deep-merge semantics for state outputs.
- No fully generic action executor in the engine (Actions are planned; Steps execute them).

---

## 2. Headless Core

The IdLE engine core is **headless**:

- No interactive prompts
- No direct authentication flows
- No UI responsibilities
- No global session/caching requirements

-> Ensures IdLE.Core runs identically in CLI, server, and test environments.
-> Keeps the engine deterministic and testable.
-> Prevents UI/auth dependencies from leaking into orchestration logic.

---

## 3. Data-Driven Workflows

### 3.1 Workflow and Metadata Formats

- Workflows are defined in **PSD1**.
- Step metadata is defined in **PSD1**.
- YAML is explicitly postponed (dependency-free).
- JSON is avoided for authoring because it cannot contain comments and hard to read.

-> PSD1 is built-in to PowerShell and supports comments.
-> Data-only files enable strict validation and safe review.

---

## 4. Strict Validation

IdLE uses **Strict** validation for configuration and planning:

- Unknown keys are errors.
- Missing required inputs are errors.
- Mutually exclusive inputs are errors.
- Declarative conditions and paths are validated before execution.

-> Avoids silent misconfiguration.
-> Shifts failures to **Plan/Validate time** instead of runtime.

---

## 5. Conditions (Declarative Only)

- Conditions are **declarative** objects, not PowerShell expressions.
- Allowed roots for condition paths: `Request`, `State`, `Policy` (optional).

-> Declarative conditions are safe and statically validatable.
-> No expression parsing/execution reduces risk and runtime failures.

---

## 6. References: Field-Based “From” Convention

We use the field-based reference convention:

- Literal value: `Value = <literal>`
- Reference: `ValueFrom = 'Request.X'` or `ValueFrom = 'State.Y'`
- Optional fallback: `ValueDefault = <literal>`

**No implicit interpretation** of plain strings as references.

- Readable in PSD1.
- Strictly validatable without executing code.
- Clean separation of literal vs. referenced values.
- Validate **paths** (`*From`) strictly.
- Do **not** enforce strong typing for all literals (Steps may validate/cast) - yet.

---

## 7. Request vs. Plan vs. Execute

### 7.1 LifecycleRequest

**LifecycleRequest** is the domain input representing business intent:

- LifecycleEvent (Joiner/Mover/Leaver/…)
- IdentityKeys (UPN, EmployeeId, ObjectId, …)
- DesiredState (attributes, entitlements, etc.)
- Changes (for mover lifecycle events)
- CorrelationId (required; generated if missing)

### 7.2 LifecyclePlan

**LifecyclePlan** is derived from Request + Workflow + Step Catalog:

- Evaluated steps (run/skip via conditions)
- Planned data-only Actions
- Warnings/required inputs
- State outputs produced during planning (if applicable)
- Workflow identity (id/version) for audit

### 7.3 Execute Phase

**Execute** runs **only the plan**:

- No re-evaluation of conditions
- No re-testing / re-planning
- Deterministic “do what the plan says”

-> Enables preview and approval patterns.
-> Improves auditability and repeatability.
-> Avoids “plan drift” between preview and execution.

---

## 8. Public Cmdlet API

IdLE exposes four core cmdlets:

| Cmdlet | Purpose |
| --- | --- |
| `Test-IdleWorkflow` | Validate workflow and step metadata (config correctness) |
| `New-IdleLifecycleRequest` | Create/normalize a LifecycleRequest |
| `New-IdlePlan` | Build a plan (preview) |
| `Invoke-IdlePlan` | Execute a plan deterministically |

-> `Test-IdleWorkflow` is **not** an operational execution tool.
-> Operational flow: Request → Plan → Execute
-> Clear separation of responsibilities.
-> CI/CD-friendly workflow validation.
-> Easier testing and maintenance than monolithic cmdlets.

---

## 9. Steps, Metadata, and Handler Resolution

### 9.1 Step Model

Steps are reusable plugins that:

- plan data-only actions in `Test-*`
- execute actions in `Invoke-*`
- (Later) implement `Rollback-*`

### 9.2 Step Metadata

Each step has a metadata PSD1 file describing:

- Allowed keys in `With`
- Required keys
- Mutually exclusive keys
- Declared outputs (State ownership)
- Optional explicit handlers

### 9.3 Handler Resolution (Hybrid)

Resolution order:

1. Use explicit `Handlers` from metadata (if present)
2. Else use naming convention:
   - `Test-JmlStep<StepId>` (or IdLE naming; project decides final prefix)
   - `Invoke-JmlStep<StepId>`
   - optional `Rollback-JmlStep<StepId>`

> Note: We intentionally support both to enable future refactoring without breaking workflows.

-> Conventions enable quick start.
-> Explicit handlers enable refactoring/versioning later without changing StepId in workflows.

---

## 10. Actions

- Steps produce **data-only actions** during planning.
- Steps execute their own actions during `Invoke-*` (engine does not interpret action semantics in V1).
- Actions use a **namespaced `Op`** value:
  - `Identity.*`, `Entitlement.*`, `External.*`, `Custom.*`

---

## 11. State and Outputs

### 11.1 State Roots

- `State.*` is engine-managed runtime/planning state.

### 11.2 Output Rules (Strict)

- Steps may only write to `State.*`.
- Steps may only write to **declared output paths** from metadata.
- Steps may not overwrite output paths owned by other steps.

### 11.3 Merge Semantics

- **Replace-at-path** only (no deep merge).
- Overwrites are allowed only for the same step (e.g., retries), not across steps.

-> Keeps dataflow explicit and validatable.
-> Prevents state collisions.
-> Avoids complex merge semantics in V1.

---

## 12. Execution Semantics

- Sequential step execution.
- **Fail-fast**: stop plan execution on first step failure.
- No automatic rollback orchestration in V1.
- Execution produces structured events (audit/progress) via sinks.

-> Predictable and auditable behavior.
-> Rollback semantics are domain-specific and often not reversible.
-> “Compensation” is treated as a separate workflow/process.

---

## 13. Authentication and Identity

- V1 does not require an `Actor` field in the request.

- Target systems often require and audit **personal admin logins**.
- A request-level actor claim is not verifiable by the engine and can be misleading.

### 13.2 Auth belongs to Providers

- Steps do not perform authentication.
- Providers handle authentication and obtain sessions through an ExecutionContext provided by the host.

-> Prevents UI/auth code from leaking into the engine.
-> Supports heterogeneous target systems with different auth modes.

### 13.3 AuthProfile + ExecutionContext callback

- Steps may reference an `AuthProfile` label (no secrets).
- Providers request sessions via:
  - `ExecutionContext.AcquireSession(providerAlias, authProfile, requirements)`

The **host** (CLI/service) implements:

- interactive login flows
- MFA handling
- credential/session caching (optional)
- enforcement of “interactive allowed/not allowed”

-> Different steps/providers may require different accounts and auth methods (incl. MFA).
-> Keeps engine headless while enabling personalized admin logins.

---

## 14. Provider/Adapter Pattern

IdLE.Core communicates only with contracts/ports (interfaces), never directly with systems.

Examples of ports:

- Identity provider
- Entitlement provider
- External system providers (ticketing/HR)
- Event/Audit sinks

-> Swappable implementations
-> Strong testability via mocks
-> Separation of orchestration vs. system-specific logic

---

## Appendix A: Architecture Diagram

```mermaid
flowchart LR
    Host[Host / CLI / Service]
    Engine[IdLE Core Engine]
    Workflow[Workflow (PSD1)]
    Steps[Step Plugins]
    Providers[Providers]
    Targets[Target Systems]

    Host -->|ExecutionContext| Engine
    Host -->|Load| Workflow

    Engine --> Workflow
    Engine --> Steps

    Steps --> Providers
    Providers -->|AcquireSession(...)| Host

    Providers --> Targets
```

---

## Appendix B: Open Items / V2 Candidates (Not in V1)

- Deep merge semantics for State outputs (if needed)
- Generic execution of core `Op` namespaces in the engine
- Automatic rollback orchestration (if domain demands it)
- YAML support (optional; introduces dependency)
- Verified actor / requestor claims (if host can provide verified identity)

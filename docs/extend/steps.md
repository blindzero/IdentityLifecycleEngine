# Steps and Metadata

## Purpose

Steps are the fundamental building blocks of execution in IdLE.
They encapsulate domain logic and perform concrete actions during the execution
of a lifecycle plan.

This document defines the conceptual model of a step, the meaning of step metadata,
and the expectations placed on step implementations. It serves as a normative
reference for step authors and reviewers.

---

## Scope

This document covers:

- What a step represents conceptually
- The lifecycle of a step during plan execution
- The role and meaning of step metadata
- Expectations regarding idempotency and side effects
- Responsibility boundaries between steps and other components

Out of scope:

- Inventory or listing of existing steps
- Step-specific parameter reference
- Provider-specific implementation details
- Code examples of individual steps

---

## Concept

### What is a step?

A step is a **self-contained unit of work** executed as part of a plan.

A step:

- performs a single, well-defined responsibility
- operates on the execution context provided by the engine
- may interact with external systems through providers
- reports its outcome through status and events

Steps do not orchestrate other steps and do not control execution flow beyond
their own outcome.

---

### Step lifecycle

During execution, each step follows a consistent lifecycle:

1. The engine signals the start of the step
2. The step evaluates its own applicability (if applicable)
3. The step performs its domain logic
4. The step reports its result and any relevant events

The engine is responsible for invoking steps and sequencing their execution.

---

### Step metadata

Metadata describes **what a step is**, not **how it is implemented**.

Typical conceptual metadata includes:

- **Name**
  - Human-readable identifier
- **Purpose**
  - Description of what the step is intended to achieve
- **Idempotency**
  - Whether repeated execution leads to the same state
- **Inputs**
  - Expected configuration values or request data
- **Outputs**
  - State changes or information produced
- **Side effects**
  - External systems affected by the step

Metadata exists to make steps:

- understandable
- reviewable
- documentable

---

### Idempotency expectations

Steps should be designed to be **idempotent whenever possible**.

Idempotent steps:

- can be executed multiple times without unintended side effects
- are safer in retries and error recovery scenarios
- improve predictability of plans

If a step is not idempotent, this must be clearly documented in its metadata.

---

### Side effects and responsibility

Steps are the only components allowed to produce side effects.

However:

- side effects must be explicit and intentional
- steps must not perform hidden or implicit changes
- external interactions must be delegated to providers

This keeps side effects observable and testable.

---

## Usage

### Writing steps

When writing a new step, authors should:

- keep the responsibility narrow and focused
- rely only on documented provider contracts
- emit meaningful events for observability
- respect idempotency expectations
- avoid embedding configuration or environment assumptions

---

### Steps and configuration

Configuration supplies **parameters** to steps.
It must not replace step logic.

Steps should:

- interpret configuration declaratively
- validate required inputs
- remain functional across environments

---

### Steps and providers

Steps interact with external systems exclusively through providers.

Steps must not:

- access infrastructure directly
- assume provider implementation details
- embed credentials or environment-specific values

---

## Common pitfalls

### Overloading steps

Steps that attempt to do too much:

- become hard to test
- blur responsibility boundaries
- reduce reuse

Prefer composing multiple focused steps instead.

---

### Encoding logic in configuration

Complex logic does not belong in configuration.

If a workflow becomes hard to read, the logic likely belongs in a step.

---

### Ignoring metadata

Undocumented behavior leads to:

- fragile steps
- unclear reviews
- broken expectations

Metadata is not optional; it is part of the step contract.

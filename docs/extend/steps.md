# Steps and Metadata

## Purpose

Steps are the fundamental building blocks of execution in IdLE.
They encapsulate domain logic and perform concrete actions during the execution
of a lifecycle plan.

This document defines the conceptual model of a step, the meaning of step metadata,
and the expectations placed on step implementations. It serves as a normative
reference for step authors and reviewers.

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

### Design goals

Steps should be:

- idempotent (converge towards the desired state)
- deterministic (same inputs produce the same plan)
- provider-agnostic (use provider contracts, not direct system calls)
- safe for preview (planning must not change external state)

### Step lifecycle

During execution, each step follows a consistent lifecycle:

1. The engine signals the start of the step
2. The step evaluates its own applicability (if applicable)
3. The step performs its domain logic
4. The step reports its result and any relevant events

The engine is responsible for invoking steps and sequencing their execution.

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

### Idempotency expectations

Steps should be designed to be **idempotent whenever possible**.

Idempotent steps:

- can be executed multiple times without unintended side effects
- are safer in retries and error recovery scenarios
- improve predictability of plans

If a step is not idempotent, this must be clearly documented in its metadata.

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

### Steps and configuration

Configuration supplies **parameters** to steps.
It must not replace step logic.

Steps should:

- interpret configuration declaratively
- validate required inputs
- remain functional across environments

### Steps and providers

Steps interact with external systems exclusively through providers.

Steps must not:

- access infrastructure directly
- assume provider implementation details
- embed credentials or environment-specific values

## Inputs

Steps receive inputs from the workflow under `Inputs` and may reference:

- `Request.*`
- `State.*`
- `Policy.*` (optional root, host-defined)

### Security: Data-only constraint

**All step inputs must be data-only and must not contain ScriptBlocks.**

Step implementations MUST validate their inputs using the centralized helper:

```powershell
Assert-IdleNoScriptBlock -InputObject $config -Path 'With.Config'
```

The `Assert-IdleNoScriptBlock` function is exported from `IdLE.Core` and recursively validates hashtables, arrays, and PSCustomObjects.

**Do not implement custom ScriptBlock validation.** Use the centralized helper to ensure consistent enforcement across all steps.

---

## Outputs

Steps may write to `State.*` only, and only to declared output paths.
This prevents hidden coupling between steps.

### Eventing

Steps may emit **structured events** for progress and audit.

The engine provides a stable, object-based contract on the execution context:

- `Context.EventSink.WriteEvent(Type, Message, StepName, Data)`

Notes:

- `Type` is a short string (for example: `Custom`, `Debug`).
- `Message` is a human-readable message.
- `StepName` should be the current step name (if available).
- `Data` is an optional hashtable for structured details.

Example:

```powershell
$Context.EventSink.WriteEvent(
  'Custom',
  'Ensured Department attribute.',
  $Step.Name,
  @{ Provider = 'Identity'; Attribute = 'Department' }
)
```

- Steps must never execute code from configuration.
- Steps must not assume a specific host UI.
- Hosts can optionally stream events via `Invoke-IdlePlan -EventSink <object>`,
  but **ScriptBlock sinks are not supported**.

---

## Error behavior

### Primary steps (fail-fast)

IdLE uses a **fail-fast execution model** for primary workflow steps:

- A failing step stops plan execution immediately
- Subsequent primary steps are not executed
- Results and events capture what happened up to the failure

### OnFailureSteps (best-effort)

When primary steps fail, workflows can define **OnFailureSteps** for cleanup or rollback.

OnFailureSteps are executed in **best-effort mode**:

- Each OnFailure step is attempted regardless of previous OnFailure step failures
- OnFailure step failures do not stop execution of remaining OnFailure steps
- The overall execution status remains 'Failed' even if all OnFailure steps succeed

**Execution result structure:**

```powershell
$result.Status                # 'Failed' when primary steps fail
$result.Steps                 # Array of primary step results (only executed steps)
$result.OnFailure.Status      # 'NotRun', 'Completed', or 'PartiallyFailed'
$result.OnFailure.Steps       # Array of OnFailure step results
```

**OnFailure status values:**

- `NotRun`: No primary steps failed, OnFailure steps were not executed
- `Completed`: All OnFailure steps succeeded
- `PartiallyFailed`: At least one OnFailure step failed, but execution continued

For details on declaring OnFailureSteps, see [Workflows](../use/workflows.md).

---

## Common pitfalls

### Overloading steps

Steps that attempt to do too much:

- become hard to test
- blur responsibility boundaries
- reduce reuse

Prefer composing multiple focused steps instead.

### Encoding logic in configuration

Complex logic does not belong in configuration.

If a workflow becomes hard to read, the logic likely belongs in a step.

### Ignoring metadata

Undocumented behavior leads to:

- fragile steps
- unclear reviews
- broken expectations

Metadata is not optional; it is part of the step contract.

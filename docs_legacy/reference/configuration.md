# Configuration

## Purpose

Configuration in IdLE defines *what* should happen during a lifecycle execution,
not *how* it is implemented.

This document explains the conceptual role of configuration in IdLE, the different
levels at which configuration exists, and how responsibilities are intentionally
separated to keep workflows portable, testable, and reusable.

---

## Scope

This document covers:

- The role of configuration in IdLE
- Different configuration layers and their responsibilities
- How configuration influences planning and execution
- Recommended configuration patterns

Out of scope:

- Complete workflow schema documentation
- Provider-specific configuration options
- Implementation details of steps or providers
- Validation rules for individual configuration properties

---

## Concept

### Configuration as declarative intent

Configuration in IdLE is **declarative**.

It describes:

- desired state
- required steps
- conditions under which steps apply

It does not describe:

- execution order mechanics
- infrastructure-specific behavior
- side effects

This allows IdLE to build and execute plans deterministically based on intent.

---

### Configuration layers

IdLE uses multiple configuration layers with clear boundaries:

#### Workflow configuration

- Defines lifecycle intent
- Declares steps, conditions, and parameters
- Declares optional OnFailureSteps for cleanup/rollback
- Is environment-agnostic
- Stored as version-controlled files (e.g. PSD1)

**OnFailureSteps** are an optional workflow section that defines cleanup or rollback steps
executed when primary steps fail. They run in best-effort mode: each OnFailure step is attempted
regardless of previous OnFailure step failures.

#### Execution request

- Describes *why* a workflow is executed
- Includes lifecycle event, actor, and context
- Supplied at runtime by the host

#### Provider configuration

- Defines how external systems are accessed
- Is environment-specific
- Managed entirely by the host

The engine combines these layers when building a plan.

---

### Workflow configuration is portable

Workflow configuration must remain:

- deterministic
- side-effect free
- independent of environment

A workflow should not:

- reference credentials
- embed infrastructure details
- assume a specific provider implementation

This ensures the same workflow can run unchanged in:

- local development
- CI pipelines
- production environments

---

### Conditions and intent

Conditions are part of configuration, not logic.

They express:

- when a step should apply
- based on input state or request context

Conditions must not:

- perform mutations
- depend on external systems
- replace step logic

They are evaluated during planning, not execution.

---

## Usage

### When to use configuration

Configuration should be used to express:

- *what* needs to be ensured
- *under which circumstances*
- *with which parameters*

Examples include:

- ensuring attributes
- assigning entitlements
- skipping steps based on request data

---

### When not to use configuration

Configuration should not be used to:

- encode complex logic
- perform calculations
- replace step implementations

If behavior cannot be expressed declaratively, it likely belongs in a step.

---

### Host responsibility

The host is responsible for:

- loading workflow configuration
- supplying execution requests
- providing provider implementations
- validating configuration before execution (if required)

The engine assumes configuration is valid and focuses on orchestration.

---

## Common pitfalls

### Mixing configuration and logic

Embedding logic into configuration leads to:

- unreadable workflows
- fragile behavior
- difficult testing

Logic belongs in steps, not configuration.

---

### Environment-specific configuration in workflows

Workflows must not contain:

- credentials
- hostnames
- environment-specific identifiers

Such data belongs in host configuration and provider setup.

---

### Overloading configuration

Trying to solve every problem with configuration often results in
overly complex workflows.

Prefer small, focused steps with clear parameters.

---

## Related documentation

- [Workflows](../usage/workflows.md)
- [Steps](../usage/steps.md)
- [Providers and Contracts](providers-and-contracts.md)
- [Events and Observability](events-and-observability.md)
- [Architecture](../advanced/architecture.md)

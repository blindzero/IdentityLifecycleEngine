---
title: Concepts
sidebar_label: Concepts
---

# IdLE Concepts

IdLE stays headless and avoids responsibilities that belong to a host application.

## Goals

- Generic, configurable lifecycle orchestration (Joiner / Mover / Leaver)
- Portable, modular, testable
- Headless core (works in CLI, service, CI)
- Plan-first execution with structured events

## Non-goals

- No UI framework or service host
- no interactive prompts
- no authentication flows inside steps
- No dynamic code execution from configuration
- No automatic rollback orchestration
- No deep merge semantics for state outputs

---

## Responsibilities

### Separation of Responsibility

Clear separation of responsibility is the essential foundation for maintainability:

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

---

IdLE consists of the following elements and components:

## Request

A **LifecycleRequest** represents the business intent (for example: Joiner, Mover, Leaver). It is the input to planning.

```powershell
$Request = New-IdleLifecycleRequest -LifecycleEvent 'Joiner' -IdentityKeys @{
    key = 'first.last'
}
-DesiredState @{
    Firstname = 'First'          
    Lastname = 'Last'
    Mail = 'First.Last@domain.tld'
}
```

---

## Workflow

Workflows are **data-only configuration files** (PSD1) describing which steps should run for a lifecycle event. 
To enable larger flexibility, you can use placeholders instead of literals to be substituted with data from request.

```powershell
@{
    Name           = 'Joiner - Workflow Workflow'
    LifecycleEvent = 'Joiner'
    Steps          = @(
        @{
            Name = 'Step Name'
            Type = 'IdLE.Step.StepType'
            With = @{
                # Passed with values from Request Data
                IdentityKey = '{{Request.IdentityKeys.key}}'
                Attributes  = @{
                    GivenName         = 'Firstname'
                    # Passed with values from Request Data
                    Surname           = '{{Request.DesiredState.Lastname}}'                    
                }
                Provider    = 'IdentityProvider'
            }
        }
```

### Steps

**Steps** are reusable plugins that define convergence logic. They:

- Operate idempotently (converge towards desired state)
- Are provider-agnostic (use contracts, not direct system calls)
- Emit structured events for audit and progress
- Define the capabilities a provider has to supply to be eligible to perform a step

Steps may only write to `State.*` and only to declared output paths.
No deep merge: replace-at-path semantics only.

Learn more: [Steps](../use/steps.md) | [Step Catalog](../reference/steps.md)

### Providers

**Providers** are system-specific adapters that connect workflows to external systems. They:

- Authenticate and manage sessions
- Translate generic operations to system APIs
- Are mockable for tests

Learn more: [Providers](../use/providers.md) | [Providers and Contracts](../extend/providers.md)

### Declarative conditions

Steps can contain conditions which are data-only objects.
They are validated early and evaluated deterministically.

```powershell
Condition = @{
    Equals = @{
        Path   = 'Plan.LifecycleEvent'
        Value  = 'Joiner'
    }
}
```

---

## Plan

IdLE builds a **deterministic execution plan** before any step is executed.

The plan is created deterministically from:

- request data
- workflow definition
- step catalog / step registry
- authentication session informations

During this planning phase, the engine validates structural correctness,
conditions, and execution prerequisites.

- evaluates declarative conditions
- validates inputs and references
- produces data-only actions
- captures a **data-only request intent snapshot** (e.g. IdentityKeys / DesiredState / Changes) for auditing and export

### Provider Capabilities (Planning-time Validation)

IdLE uses a **capability-based provider model** to validate execution
prerequisites during plan build.

Steps may declare required capabilities, while providers explicitly
advertise which capabilities they support. The engine matches both sides
and fails fast if required functionality is missing.

For details on the capability-based provider model and the validation flow,
see [Provider Capabilities](../reference/capabilities.md).

### Plan export

Hosts may persist or exchange a plan as a **machine-readable JSON artifact**.
The canonical contract format is defined here:

- [Plan export specification (JSON)](../reference/specs/plan-export.md)

The exported artifact is intended for **approvals, CI checks, and audits**.
To keep exports deterministic and review-friendly, the contract intentionally omits volatile information
such as engine build versions and timestamps. When required, hosts SHOULD attach build/time metadata
outside the exported plan artifact.

Because IdLE separates planning from execution, the plan retains a **request intent snapshot** so that
exports can include `request.input` even after the original request object is no longer available.

---

## Execute

Execution runs **only the plan** (no re-planning). This supports:

- approvals
- repeatability
- deterministic audits

### Eventing

IdLE emits **structured events** during execution.

- The engine always creates an `EventSink` and exposes it as `Context.EventSink`.
- Steps and the engine use a single contract: `Context.EventSink.WriteEvent(Type, Message, StepName, Data)`.
- All events are buffered in the execution result (`result.Events`).

Hosts may optionally provide an external sink to stream events live:

- `Invoke-IdlePlan -EventSink <object>`
- The sink must implement `WriteEvent(event)`
- ScriptBlock sinks are rejected (secure default)

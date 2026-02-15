---
title: IdLE Concepts
sidebar_label: Concepts
---

IdLE is a generic, headless, configuration-driven engine for identity lifecycle automation (Joiner / Mover / Leaver). It intentionally separates intent from implementation: workflows (data-only PSD1 files) declare what should happen, steps implement provider-agnostic, idempotent convergence logic, and providers adapt to external systems and manage authentication.

The engine first builds a deterministic, auditable execution plan from a LifecycleRequest and a workflow (Plan → Execute). Planning validates conditions, inputs, and required provider capabilities; execution runs only the produced plan to ensure repeatability, safe approvals, and reliable auditing. This design prioritizes portability, testability (mockable providers), and minimal runtime assumptions by keeping the core headless and side-effect free.

## Goals

- Generic, configurable lifecycle orchestration (Joiner / Mover / Leaver)
- Portable, modular, testable
- Headless core (works in CLI, service, CI)
- Plan-first execution with structured events

## Non-goals

- No UI framework or service host
- No interactive prompts
- No authentication flows inside steps
- No dynamic code execution from configuration
- No automatic rollback orchestration
- No deep merge semantics for state outputs

---

## Components

IdLE consists of the following elements and components, which have clear and distinct boundaries to separate their responsibilities and make maintainability easier. This separation keeps the core engine free of environmental assumptions.

### Host

The host is technically not really a component of IdLE. It is the environment in which IdLE is running, so your PowerShell console, scripting session or whatever is used to run IdLe. The host

- Selects and configures providers
- Injects providers into plan execution
- Decides which provider implementations are used

### Engine (basically IdLE.Core)

IdLE.Core is the central engine (module) of IdLE and performs the most central tasks

- Orchestrates workflow execution
- Invokes steps
- Passes providers to steps
- Never depends on provider internals
- Authentication session brokerage

## Request

A **LifecycleRequest** represents the business intent (for example: Joiner, Mover, Leaver). It is the input to planning.

```powershell
$Request = New-IdleRequest -LifecycleEvent 'Joiner' -IdentityKeys @{
    key = 'first.last'
} -DesiredState @{
    Firstname = 'First'          
    Lastname = 'Last'
    Mail = 'First.Last@domain.tld'
}
```

### Workflow and Steps

**Workflows** are **data-only configuration files** (PSD1) describing which steps should run for a lifecycle event. Usually workflows are written in `psd1` files, that

- use Data-only PSD1 configuration (no ScriptBlocks or executable objects)
- declare step sequence by Type string and provide per-step With parameters
- may use placeholders referencing Request data; substitutions occur during planning
- serve as deterministic, reviewable input to the planner (suitable for approvals and audits)
- must not perform authentication, call providers directly, or contain imperative logic
- Validated early and evaluated deterministically by the engine

```powershell
@{
    Name           = 'Joiner - Example Workflow'
    LifecycleEvent = 'Joiner'
    Steps          = @(
        @{
            Name = 'Step Name'
            # The step type which defines which capabilities a provider has to supply to execute the step 
            Type = 'IdLE.Step.StepType'
            With = @{
                # Passed with values from Request Data
                IdentityKey = '{{Request.IdentityKeys.key}}'
                Attributes  = @{
                    # Fixed string example
                    GivenName         = 'Firstname'
                    # Passed with values from Request Data
                    Surname           = '{{Request.DesiredState.Lastname}}'                    
                }
                # Any identifier you choose, which references to the provider used in the plan and invocation
                Provider    = 'IdentityProvider'
            }
        }
    )
}
```

**Steps** are **reusable plugins** used by workflows that define convergence logic. They:

- Implement idempotent domain logic (converge towards desired state).
- Declare required capabilities (by name) and consume providers via those capability contracts.
- Step types identify the step implementation, they are not capabilities! Capabilities (namespaced IdLE.* contract names) describe provider functionality that steps require; do not conflate the two.
- Are provide-agnostic via capability contracts, and do not provide any concrete system calls.
- Emit structured events for audit and progress
- **Important:** Steps must not handle authentication — authentication is a provider responsibility (AuthSessionBroker).

Learn more: [Workflows](../use/workflows.md) | [Step Catalog](../reference/steps.md)

### Providers

**Providers** are system-specific adapters that connect workflows to external systems. They:

- Translate generic operations to system APIs to implement infrastructure-specific behavior
- Advertise which capabilities they fulfill and map capability operations to system APIs and fulfill contracts expected by steps (as defined by capability names)
- Authenticate and manage sessions
- Are mockable for tests
- Avoid global state

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

### **Capabilities**

IdLE uses a **capability-based provider model** to validate execution prerequisites during plan build.
Steps may declare required capabilities, while providers explicitly advertise which capabilities they support. The engine matches both sides
and fails fast if required functionality is missing. Capabilities are the "glue" between provider-agnostic Steps and the system-specific providers. They are

- named, namespaced contracts (e.g., `IdLE.Identity.Read`) that describe the operations/shape a provider must expose
- declared by steps as required capabilities and advertised by providers at registration
- matched during planning: the engine validates required capabilities are available and fails fast if not

For details on the capability-based model see [Provider Capabilities](../reference/capabilities.md).

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

---

## Execute

Execution runs **only the plan** (no re-planning). This supports:

- approvals
- repeatability
- deterministic audits

IdLE emits **structured events** during execution which allows post-execution check on overall status or per-step results and messages.

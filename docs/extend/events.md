---
title: Events
sidebar_label: Events
---

# Events and Observability

## Purpose

Events in IdLE provide a structured way to observe what happens during the execution
of a lifecycle plan. They are designed to make plan execution transparent for hosts,
operators, and tooling without coupling the core engine to any specific logging,
monitoring, or UI framework.

This document explains the conceptual model behind events in IdLE, their lifecycle,
and how they are intended to be consumed.

---

## Scope

This document covers:

- Why events exist in IdLE
- Where and when events are created
- How events are collected and exposed
- Responsibilities of engine, steps, and host environments
- Recommended usage patterns

Out of scope:

- Detailed API or property reference of event objects
- Logging frameworks or telemetry backends
- Implementation details of specific steps

---

## Concept

### Events are observability signals, not logging

IdLE events are **not a logging system**.

They represent **semantic execution milestones**, such as:

- a plan starting or completing
- a step being executed or skipped
- a step emitting a domain-relevant message

The core engine does not decide:

- where events are stored
- how they are rendered
- whether they are logged, streamed, or ignored

Those decisions belong to the **host environment**.

---

### Event creation model

Events are created at well-defined points during plan execution:

- **Run-level events**
  - `RunStarted`
  - `RunCompleted`

- **Step-level events**
  - `StepStarted`
  - `StepCompleted`
  - `StepFailed`
  - `StepSkipped`

- **Custom events**
  - Explicitly emitted by steps (for example via an `EmitEvent` step)

All events share a common intent:
> describe *what happened*, not *how it should be presented*.

---

### Buffered by default

During execution, events are **buffered inside the execution result**.

This means:

- The engine can run in completely headless environments
- No output is produced unless the host explicitly consumes events
- Events are always available after execution for inspection

Buffering is the default because it keeps the core:

- deterministic
- testable
- independent of runtime context

---

### Optional streaming to a host sink

Hosts may provide an **event sink** to receive events as they happen.

The engine expects an object with a `WriteEvent(event)` method.
If present, the engine forwards each event to that sink **in addition to** buffering
events in the execution result.

This enables patterns such as:

- forward events to a central logging system
- push events to a message bus
- render progress updates in an interactive host

The engine still does not assume anything about formatting, persistence, or transport.

---

## Usage

### Typical consumption patterns

Different hosts consume events differently:

#### CLI tools and demos

- Collect all events
- Render them after execution in a human-readable form
- Optionally summarize counts or highlight failures

The repository demo runner is an example of this pattern.

#### CI pipelines

- Inspect execution status
- Fail the pipeline if a `RunFailed` or `StepFailed` event exists
- Optionally archive event output as build artifacts

#### Services and long-running hosts

- Execute plans headlessly
- Forward buffered events to logging, tracing, or messaging systems
- Decide independently whether events are streamed or processed asynchronously

---

### Responsibilities

Clear responsibility boundaries are essential:

- **Engine**
  - Creates events at defined lifecycle points
  - Buffers events in execution results
  - Does not format, log, or persist events

- **Steps**
  - May emit custom, domain-specific events
  - Must not assume how or where events are displayed

- **Host**
  - Decides how events are consumed
  - May format, log, store, or forward events
  - May ignore events entirely

This separation ensures that IdLE remains portable and reusable across environments.

---

## Security and sensitive data

Events are a primary observability surface and therefore a common place where sensitive
values can accidentally leak.

Guidelines:

- **Do not emit secrets** in `Event.Data` (tokens, passwords, client secrets, API keys, certificates).
- Prefer **references** (for example: identity IDs, step names, correlation IDs) over raw payloads.
- The engine applies **redaction** at output boundaries (buffered events and host sinks) for
  common sensitive key names (for example: `password`, `token`, `secret`, `apiKey`).
  Redaction is a safety net, not a design strategy.
- When acquiring authentication sessions, use `Providers.AuthSessionBroker` via
  `Context.AcquireAuthSession(Name, Options)`. Auth session options are a data-only boundary
  and reject ScriptBlocks.

---

## Common pitfalls

### “Why don’t I see any events?”

Events are not written to the console automatically.
If a host does not explicitly render or process events, they remain buffered only.

This is intentional.

---

### Treating events as log output

Events should not be used as a replacement for structured logging.
They represent execution semantics, not debug traces.

If detailed diagnostics are required, hosts should integrate their own logging
mechanisms alongside IdLE execution.

---

### Mixing engine and host responsibilities

The engine must never:

- write directly to the console
- depend on a logging framework
- assume interactive execution

Violating this separation would break testability and portability.

---

## Related documentation

- [Workflows](../use/workflows.md)
- [Steps](../use/steps.md)
- [Providers](../use/providers.md)
- [Architecture](../about/architecture.md)

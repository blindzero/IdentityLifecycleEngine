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
- Event types, levels and data fields
- Responsibilities of engine, steps, and host environments
- Recommended usage patterns

Out of scope:

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

- **Run-level events** (`IdLE.Run.*`) when a plan starts and finishes
- **Step-level events** (`IdLE.Step.*`, `IdLE.OnFailure.*`) when a step starts, completes, fails or is skipped
- **Domain events** emitted by steps and providers (for example `IdLE.Step.DirectorySync.Completed`)
- **Workflow-defined events** from `PreconditionEvent` and the `IdLE.Step.EmitEvent` step

All events share a common intent:
> describe *what happened*, not *how it should be presented*.

---

### Event object

Every event is an object with `PSTypeName = 'IdLE.Event'`:

| Property | Description |
| --- | --- |
| `TimestampUtc` | UTC timestamp. |
| `Type` | What happened (see [Event types](#event-types)). |
| `Level` | How severe it is: `Information`, `Warning` or `Error`. |
| `Message` | Human-readable message. Do not parse it; use `Type` and `Data`. |
| `CorrelationId` | Correlation ID of the request. |
| `Actor` | Actor of the request. |
| `StepName` | Name of the step (empty for run-level events). |
| `Data` | Optional hashtable with structured details (redacted at output boundaries). |

Steps and providers write events through the execution context:

```powershell
$Context.EventSink.WriteEvent(Type, Message, StepName, Data[, Level])
```

`Level` is optional and defaults to `Information`.

---

### Event types

`Type` names the event; `Level` carries the severity. Sinks filter on both (for example: alert on
`Level = 'Error'`, audit on `IdLE.Provider.AD.AttributeChanged`).

| Emitted by | Format | Example |
| --- | --- | --- |
| IdLE (engine, first-party steps and providers) | `IdLE.<Area>.<Event>` | `IdLE.Step.Failed`, `IdLE.Provider.AD.AttributeChanged` |
| Extensions (third-party steps and providers) | `<Owner>.IdLE.<Area>.<Event>` | `Contoso.IdLE.Hr.ManagerSynced` |
| Workflows (`PreconditionEvent.Type`, `EmitEvent` `With.Type`) | free, but not `IdLE.*` | `Contoso.ManualActionRequired` |

Rules:

- `IdLE.*` is reserved for events emitted by IdLE. Workflow-defined event types starting with `IdLE.`
  are rejected (`ReservedNamespace`); see [Step type names](steps.md#step-type-names) for the namespace scheme.
- `Information`, `Warning`, `Error` and `Custom` are not valid event types (`InvalidEventType`).
  Use a descriptive type and set the severity with `Level`.
- Event types and their `Data` fields listed below are a contract. `Message` texts are not.

#### Engine events

| Type | Level | Data |
| --- | --- | --- |
| `IdLE.Run.Started` | Information | `CorrelationId`, `Actor`, `StepCount` |
| `IdLE.Run.Completed` | Information; `Warning` if `Blocked`; `Error` if `Failed` | `Status`, `StepCount` |
| `IdLE.Step.Started` | Information | `StepType`, `Index` |
| `IdLE.Step.Completed` | Information | `StepType`, `Index` |
| `IdLE.Step.Failed` | Error | `StepType`, `Index`, `Error` |
| `IdLE.Step.Blocked` | Warning | `StepType`, `Index` |
| `IdLE.Step.NotApplicable` | Information | `StepType`, `Index` |
| `IdLE.Step.PreconditionFailed` | Warning | `StepType`, `Index`, `OnPreconditionFalse` |
| `IdLE.Step.Retrying` | Warning | `attempt`, `maxAttempts`, `delayMs`, `errorType`, `message` |
| `IdLE.OnFailure.Started` | Information | `OnFailureStepCount` |
| `IdLE.OnFailure.Completed` | Information; `Warning` if `PartiallyFailed` | `Status`, `StepCount` |
| `IdLE.OnFailure.StepStarted` | Information | `StepType`, `Index` |
| `IdLE.OnFailure.StepCompleted` | Information | `StepType`, `Index` |
| `IdLE.OnFailure.StepFailed` | Error | `StepType`, `Index`, `Error` |
| `IdLE.OnFailure.StepNotApplicable` | Information | `StepType`, `Index` |

`IdLE.Run.Completed` is always the last event of a run.

#### Step events

| Type | Level | Data |
| --- | --- | --- |
| `IdLE.Step.EmitEvent.Emitted` | `With.Level` (default Information) | `StepType` |
| `IdLE.Step.DirectorySync.Triggered` | Information | `PolicyType`, `ComputerName` |
| `IdLE.Step.DirectorySync.Waiting` | Information | `TimeoutSeconds`, `PollIntervalSeconds` |
| `IdLE.Step.DirectorySync.Polled` | Information | `Attempt`, `State`, `InProgress`, `ElapsedSeconds` |
| `IdLE.Step.DirectorySync.Completed` | Information | `Attempts`, `ElapsedSeconds` (waited) or `PolicyType` (not waited) |
| `IdLE.Step.DirectorySync.Failed` | Error | `TimeoutSeconds`, `ElapsedSeconds`, `LastKnownState` (timeout) or `Error` |
| `IdLE.Step.PruneEntitlements.Planned` | Information | `Kind`, `KeepCount`, `PruneCount` |
| `IdLE.Step.PruneEntitlements.EntitlementRevoked` | Information | `Kind`, `EntitlementId` |
| `IdLE.Step.PruneEntitlements.EntitlementSkipped` | Warning | `Kind`, `EntitlementId`, `Reason` |
| `IdLE.Step.PruneEntitlements.KeepGranted` | Information | `Kind`, `EntitlementId` |
| `IdLE.Step.PruneEntitlements.KeepGrantFailed` | Warning | `Kind`, `EntitlementId`, `Reason` |

`IdLE.Step.EmitEvent` emits `IdLE.Step.EmitEvent.Emitted` unless the workflow sets `With.Type`.

#### Provider events

Providers emit events only when the host passes an event sink to the provider.

| Type | Level | Data |
| --- | --- | --- |
| `IdLE.Provider.AD.AttributesRequested` | Information | `IdentityKey`, `Requested` |
| `IdLE.Provider.AD.AttributeChanged` | Information | `IdentityKey`, `AttributeName`, `OldValue`, `NewValue` |
| `IdLE.Provider.ExchangeOnline.PermissionsEvaluated` | Information | `MailboxSmtp`, `Right`, `CurrentUsers` |
| `IdLE.Provider.ExchangeOnline.PermissionChanging` | Information | `MailboxSmtp`, `Right`, `User`, `Action` |
| `IdLE.Provider.ExchangeOnline.PermissionsEnsured` | Information | `MailboxSmtp`, `Changed` |

#### Migration from earlier versions

Event types were renamed in one step without aliases:

| Old type | New type |
| --- | --- |
| `RunStarted`, `RunCompleted` | `IdLE.Run.Started`, `IdLE.Run.Completed` |
| `StepStarted`, `StepCompleted`, `StepFailed`, `StepBlocked`, `StepNotApplicable`, `StepPreconditionFailed`, `StepRetrying` | `IdLE.Step.Started`, `.Completed`, `.Failed`, `.Blocked`, `.NotApplicable`, `.PreconditionFailed`, `.Retrying` |
| `OnFailureStarted`, `OnFailureCompleted` | `IdLE.OnFailure.Started`, `IdLE.OnFailure.Completed` |
| `OnFailureStepStarted`, `OnFailureStepCompleted`, `OnFailureStepFailed`, `OnFailureStepNotApplicable` | `IdLE.OnFailure.StepStarted`, `.StepCompleted`, `.StepFailed`, `.StepNotApplicable` |
| `DirectorySyncTriggered`, `DirectorySyncWaiting`, `DirectorySyncPoll`, `DirectorySyncCompleted`, `DirectorySyncFailed` | `IdLE.Step.DirectorySync.Triggered`, `.Waiting`, `.Polled`, `.Completed`, `.Failed` |
| `Information` / `Warning` (PruneEntitlements) | `IdLE.Step.PruneEntitlements.Planned`, `.EntitlementRevoked`, `.EntitlementSkipped`, `.KeepGranted`, `.KeepGrantFailed` |
| `Custom` (EmitEvent) | `IdLE.Step.EmitEvent.Emitted` or the workflow's `With.Type` |
| `Provider.AD.CreateIdentity.AttributesRequested`, `Provider.AD.EnsureAttribute.AttributeChanged` | `IdLE.Provider.AD.AttributesRequested`, `IdLE.Provider.AD.AttributeChanged` |
| `Provider.ExchangeOnline.Permissions.Evaluated`, `.Applying`, `.Result` | `IdLE.Provider.ExchangeOnline.PermissionsEvaluated`, `.PermissionChanging`, `.PermissionsEnsured` |

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
- Fail the pipeline if an event with `Level = 'Error'` exists (for example `IdLE.Step.Failed`)
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

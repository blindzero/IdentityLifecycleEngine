# Architecture

This page summarizes the core architecture decisions for IdLE.

## Goals

- Generic, configurable lifecycle orchestration (Joiner / Mover / Leaver)
- Portable, modular, testable
- Headless core (works in CLI, service, CI)
- Plan-first execution with structured events

## Non-goals (V1)

- No UI framework or service host inside IdLE.Core
- No dynamic code execution from configuration
- No automatic rollback orchestration
- No deep merge semantics for state outputs

## Plan → Execute

IdLE splits orchestration into two phases.

### Plan

Planning creates a deterministic plan:

- evaluates declarative conditions
- validates inputs and references
- produces data-only actions
- captures a **data-only request intent snapshot** (e.g. IdentityKeys / DesiredState / Changes) for auditing and export

### Execute

Execution runs the plan exactly as built:

- no re-planning
- no re-evaluation of conditions

This enables previews, approvals, and repeatable audits.

## Plan export

Hosts may persist or exchange a plan as a **machine-readable JSON artifact**.
The canonical contract format is defined here:

- [Plan export specification (JSON)](../specs/plan-export.md)

The exported artifact is intended for **approvals, CI checks, and audits**.
To keep exports deterministic and review-friendly, the contract intentionally omits volatile information
such as engine build versions and timestamps. When required, hosts SHOULD attach build/time metadata
outside the exported plan artifact.

Because IdLE separates planning from execution, the plan retains a **request intent snapshot** so that
exports can include `request.input` even after the original request object is no longer available.

## Declarative conditions

Conditions are data-only objects.
They are validated early and evaluated deterministically.

## Eventing

IdLE emits **structured events** during execution.

- The engine always creates an `EventSink` and exposes it as `Context.EventSink`.
- Steps and the engine use a single contract: `Context.EventSink.WriteEvent(Type, Message, StepName, Data)`.
- All events are buffered in the execution result (`result.Events`).

Hosts may optionally provide an external sink to stream events live:

- `Invoke-IdlePlan -EventSink <object>`
- The sink must implement `WriteEvent(event)`
- ScriptBlock sinks are rejected (secure default)

## State ownership

Steps may only write to `State.*` and only to declared output paths.
No deep merge: replace-at-path semantics only.

## Extensibility

- Workflows describe intent
- Steps implement behaviors
- Providers integrate target systems

See: [Extensibility](extensibility.md).

## Trust boundaries

IdLE treats workflow configuration and lifecycle requests as **untrusted data** and validates that they contain no ScriptBlocks.

Host-provided extension points (step registry, providers, external event sinks) are **trusted inputs** and are validated for safe shapes (object contracts). For details, see `advanced/security.md`.

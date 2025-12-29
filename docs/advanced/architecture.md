# IdentityLifecycleEngine (IdLE) - Architecture

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

### Execute

Execution runs the plan exactly as built:

- no re-planning
- no re-evaluation of conditions

This enables previews, approvals, and repeatable audits.

## Declarative conditions

Conditions are data-only objects.
They are validated early and evaluated deterministically.

## State ownership

Steps may only write to `State.*` and only to declared output paths.
No deep merge: replace-at-path semantics only.

## Extensibility

- Workflows describe intent
- Steps implement behaviors
- Providers integrate target systems

See: [Extensibility](extensibility.md).

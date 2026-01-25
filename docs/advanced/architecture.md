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

IdLE builds a deterministic execution plan before any step is executed.
During this planning phase, the engine validates structural correctness,
conditions, and execution prerequisites.

- evaluates declarative conditions
- validates inputs and references
- produces data-only actions
- captures a **data-only request intent snapshot** (e.g. IdentityKeys / DesiredState / Changes) for auditing and export

#### Provider Capabilities (Planning-time Validation)

IdLE uses a **capability-based provider model** to validate execution
prerequisites during plan build.

Steps may declare required capabilities, while providers explicitly
advertise which capabilities they support. The engine matches both sides
and fails fast if required functionality is missing.

For details on the capability-based provider model and the validation flow,
see [Provider Capabilities](provider-capabilities.md).

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

## v1.0 Public API and Contracts

### Supported Commands

The **supported public API** for v1.0 consists of the following commands exported from the IdLE meta-module:

- `Test-IdleWorkflow`
- `New-IdleLifecycleRequest`
- `New-IdlePlan`
- `Invoke-IdlePlan`
- `Export-IdlePlan`
- `New-IdleAuthSessionBroker`

**Source of truth**: `src/IdLE/IdLE.psd1` → `FunctionsToExport`

Only these commands are considered **stable contracts**. Internal modules (IdLE.Core, IdLE.Steps.*, IdLE.Provider.*) are unsupported when imported directly.

### Command Contracts

For supported commands, the following are **stable contracts** (breaking changes require a major version):

- Command name
- Parameter names and parameter sets
- Observable semantics (mandatory/optional/default behavior)
- Output type identity at a coarse level (PSTypeName)

The following are **not contracts** and may change in minor/patch versions:

- Exact error message strings
- Undocumented internal object properties
- Internal module cmdlets

### Data Contracts

**Workflow authoring contract** (PSD1):
- Format: PSD1 workflow definitions validated by `Test-IdleWorkflow`
- Unknown keys: **FAIL** (strict validation)
- Required fields (Name, LifecycleEvent, Steps[].Name, Steps[].Type): **FAIL** if null/empty
- `With` payload values: allow `null` and empty strings (supports "clear attribute" scenarios)

**Lifecycle request contract**:
- Required fields: `LifecycleEvent`, `CorrelationId`
- Optional fields: `Actor`, `IdentityKeys`, `DesiredState`, `Changes`

**Plan export contract** (JSON):
- Format: JSON from `Export-IdlePlan`
- Schema and semantics are stable
- See [Plan export specification](../specs/plan-export.md)

### Capability ID Baseline (v1.0)

The following capability IDs are frozen as the v1.0 baseline:

- `IdLE.DirectorySync.Status` - Read directory sync status
- `IdLE.DirectorySync.Trigger` - Trigger directory sync
- `IdLE.Entitlement.Grant` - Grant group membership/entitlement
- `IdLE.Entitlement.List` - List user entitlements
- `IdLE.Entitlement.Revoke` - Revoke group membership/entitlement
- `IdLE.Identity.Attribute.Ensure` - Ensure identity attribute value
- `IdLE.Identity.Create` - Create identity
- `IdLE.Identity.Delete` - Delete identity
- `IdLE.Identity.Disable` - Disable identity
- `IdLE.Identity.Enable` - Enable identity
- `IdLE.Identity.Move` - Move identity (OU/container)
- `IdLE.Mailbox.Info.Read` - Read mailbox metadata/configuration
- `IdLE.Mailbox.OutOfOffice.Ensure` - Ensure Out of Office configuration
- `IdLE.Mailbox.Type.Ensure` - Ensure mailbox type (User/Shared/etc.)

**Deprecated (pre-1.0)**: `IdLE.Mailbox.Read` → automatically mapped to `IdLE.Mailbox.Info.Read` with deprecation warning during planning.

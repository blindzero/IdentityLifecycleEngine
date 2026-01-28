# IdLE Plan Export Specification

Schema-Version: 1.0  

## Overview
This document specifies the canonical, machine-readable representation of an IdLE plan export.
It defines structure, required fields, and normative rules for producers and consumers.

The exported plan is a **contract artifact**, not an internal object dump.

## Scope
This specification focuses on format and semantics.
Operational guidance is documented separately in the User Guide.

## Format
The export is a JSON document encoded in UTF-8.

---

## Design Goals

- Deterministic and reproducible
- Host-agnostic
- Human-readable (pretty-printed JSON)
- Versioned and forward-compatible
- Suitable for:
  - approval workflows
  - auditing
  - CI pipelines
  - replay and simulation

---

## Non-Goals

The plan export MUST NOT contain:

- credentials or secrets
- provider sessions or runtime handles
- script blocks or executable code
- host-specific metadata
- transient runtime state

---

## Top-Level Structure

```json
{
  "schemaVersion": "1.0",
  "engine": {
    "name": "IdLE"
  },
  "request": { },
  "plan": { },
  "metadata": { }
}
```

### schemaVersion

Version of this JSON schema (this contract).  
Independent from the IdLE engine version.

### engine

Identifies the engine that produced the exported plan.
The engine object is informational only and MUST NOT be used for contract compatibility decisions.

- engine.name is required and identifies the producing engine (e.g. IdLE).
- engine.version is intentionally omitted in this specification.

The engine version is not part of the contract to ensure stable, deterministic exports across engine version bumps.
Contract compatibility and evolution are tracked exclusively via schemaVersion.

Hosts that require engine build or release information SHOULD attach it as external metadata outside of the exported plan artifact.

---

## Request Object

Represents the **business intent** that produced the plan.

The request object captures *why* a plan was created, independent of *how* it will be executed.

```json
"request": {
  "type": "Joiner",
  "correlationId": "123e4567-e89b-12d3-a456-426614174000",
  "actor": "HR-System",
  "input": {
    "identityKeys": {
      "userId": "jdoe"
    },
    "desiredState": {
      "department": "IT"
    },
    "changes": null
  }
}
```

### Fields

| Field | Description |
| ------ | ------------- |
| type | Logical lifecycle request type (e.g. Joiner, Mover, Leaver) |
| correlationId | Stable identifier correlating request, plan, and execution |
| actor | Originator of the request (system or human), if available |
| input | Business intent payload (data-only) |

### Rules

- The `request` object represents **business intent**, not execution details.
- `input` is treated as **opaque by the engine**:
  - the engine MUST NOT rely on input semantics
  - no validation logic is implied by the export
- `input` MUST contain **data-only content**:
  - no script blocks
  - no executable expressions
  - no runtime handles
- For **IdLE-native lifecycle requests**, `input` SHOULD contain:
  - `identityKeys` – identifiers of the target identity
  - `desiredState` – intended target state
  - `changes` – explicit deltas, if applicable
- Hosts MAY include additional fields in `input`.
- The request payload is exported for **audit, approval, and traceability purposes** and MUST remain stable once the plan is created.

## Plan Object

```json
"plan": {
  "id": "plan-001",
  "mode": "PlanOnly",
  "steps": []
}
```

### Fields

| Field | Description |
| ------ | ------------ |
| id | Unique identifier of the plan |
| createdAt | (Optional) ISO-8601 UTC timestamp |
| mode | Plan lifecycle state |
| steps | Ordered list of step objects |

---

## Step Object


Each step is an **atomic, independent unit**.

```json
{
  "id": "step-01",
  "name": "Ensure Mailbox",
  "stepType": "EnsureMailbox",
  "provider": "ExchangeOnline",
  "condition": {
    "type": "when",
    "expression": "request.type == 'Joiner'"
  },
  "inputs": {
    "mailboxType": "User"
  },
  "expectedState": {
    "MailboxExists": true
  }
}
```

### Rules

- One step equals one object
- Steps are ordered and deterministic
- `stepType` is a logical identifier, not a module path
- `provider` is declarative, not an implementation reference

---

## Conditions

Conditions are **declarative** and exported **without evaluation**.

```json
"condition": {
  "type": "when",
  "expression": "request.type == 'Joiner'"
}
```

Supported types (v1):

- `when`
- `unless`
- `always`

The expression is exported as a **string**.  
Evaluation semantics are engine-internal.

---

## Expected State

`expectedState` defines the **intended outcome** of the step.

Rules:

- Pure data only
- No runtime values
- Used for audit, approval, and drift detection

---

## Metadata Object

Optional, non-semantic context information.

```json
"metadata": {
  "generatedBy": "Invoke-IdlePlan",
  "environment": "CI",
  "labels": ["preview", "dry-run"]
}
```

The engine MUST NOT rely on metadata semantics.

---

## Versioning & Compatibility

### Schema Versioning

- MAJOR: breaking changes
- MINOR: additive changes
- PATCH: clarifications only

### Engine Behavior

- Engines MUST read older schema versions
- Engines MUST reject unknown future MAJOR versions

---

## Formatting Rules

- UTF-8
- LF line endings
- Pretty-printed JSON
- Stable property ordering
- createdAt MAY be omitted for deterministic exports.

---

## Summary

The IdLE Plan Export is a **stable, auditable contract**
between planning and execution phases and between IdLE and its hosts.

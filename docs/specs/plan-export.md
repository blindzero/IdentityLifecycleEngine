# IdLE Plan Export Specification

Schema-Version: 1.0  

## Purpose

This document defines the **canonical, machine-readable JSON representation**
of a LifecyclePlan exported by IdentityLifecycleEngine (IdLE).

The exported plan is a **contract artifact**, not an internal object dump.

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
    "name": "IdLE",
    "version": "0.4.0"
  },
  "request": { },
  "plan": { },
  "metadata": { }
}
```

### schemaVersion

Version of this JSON schema (this contract).  
Independent from the IdLE engine version.

---

## Request Object

Represents the **business intent** that produced the plan.

```json
"request": {
  "type": "Joiner",
  "correlationId": "123e4567-e89b-12d3-a456-426614174000",
  "actor": "HR-System",
  "input": {
    "userId": "jdoe",
    "department": "IT"
  }
}
```

Rules:

- `input` is opaque to the engine
- No validation logic is implied by the export

---

## Plan Object

```json
"plan": {
  "id": "plan-001",
  "createdAt": "2025-01-01T10:15:00Z",
  "mode": "PlanOnly",
  "steps": []
}
```

### Fields

| Field | Description |
| ------ | ------------ |
| id | Unique identifier of the plan |
| createdAt | ISO-8601 UTC timestamp |
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

---

## Summary

The IdLE Plan Export is a **stable, auditable contract**
between planning and execution phases and between IdLE and its hosts.

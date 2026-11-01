---
title: "Design: Step State (outputs consumed by later steps)"
sidebar_label: "Design: Step State"
---

# Design: Step State

| | |
| --- | --- |
| **Status** | Proposed |
| **Issue** | [#346](https://github.com/blindzero/IdentityLifecycleEngine/issues/346) |
| **Target** | v1.0.0 |
| **Affects** | Step metadata catalogs (`StateSchema`), workflow `Precondition` and `With` (new `State.*` root), `IdLE.PlanStep` |
| **Unchanged** | Host API (`New-IdlePlan`, `Invoke-IdlePlan`), provider contract, plan export JSON contract, `Condition` |

## Problem

The step contract (#324) lets a handler return `@{ Changed; Data; State }`. `State` is meant for later steps of the
same run, but the engine only validates it as a hashtable and copies it into `IdLE.StepResult.State`. Nothing reads it.
`IdLE.Step.Mailbox.GetInfo` returns `State = @{ Mailbox = ... }` that no workflow can use.

## Principle

A step publishes **declared** State under its step name. Later steps read it through the `State.*` root in
execution-time places only (`Precondition`, `With` templates). Planning validates every reference; execution resolves it.

## 1. Declaring State outputs

A catalog entry may declare `StateSchema`, using the same key schema format as `WithSchema`:

```powershell
'IdLE.Step.Mailbox.GetInfo' = @{
    Handler              = 'Invoke-IdleStepMailboxGetInfo'
    RequiredCapabilities = @('IdLE.Mailbox.Info.Read')
    Provider             = @{ DefaultAlias = 'ExchangeOnline'; AuthSessionNameFromAlias = $true }
    WithSchema           = @{ Keys = @{ IdentityKey = @{ Type = 'String'; Required = $true } } }
    StateSchema          = @{ Keys = @{ Mailbox = @{ Type = 'Any'; Required = $true } } }
}
```

- `StateSchema` is optional. A step without it must not return `State`.
- The handler result is validated against it after the step completes (`InvalidStepHandlerResult` on mismatch,
  undeclared keys, ScriptBlocks, `PSCredential` or `SecureString`).
- Invalid schemas fail at catalog load (`InvalidStateSchema`).
- The step reference generator renders the declared keys as **Outputs (State.\*)**.

## 2. Addressing

`State.<StepName>.<Key>[.<Nested>...]`

- `<StepName>` is the `Name` of the producing step. Names used in State references must be identifiers
  (`^[A-Za-z][A-Za-z0-9_]*$`), so a producer that is referenced is named e.g. `GetMailbox`, not `Get mailbox`.
  Step names that are never referenced keep their free form.
- Step names are unique per collection (`Steps`, `OnFailureSteps`, enforced today). An `OnFailureSteps` entry that
  references a name existing in both collections fails (`StateReferenceAmbiguous`).
- Matching is case-insensitive, like all other paths.

## 3. Where State can be used

| Place | Resolved | State supported |
| --- | --- | --- |
| `Condition` | Planning | No: `StateReferenceNotAllowed` (State does not exist at planning time) |
| `Precondition` | Execution, before the step | Yes: additional root `State` |
| `With` templates `{{State.<Name>.<Key>}}` | Execution, before the step (deferred) | Yes |

### Preconditions

The precondition context is `{ Plan, Request, State }`. A State path whose producer has not published State resolves
to `$null`, like any other missing value; `Exists` distinguishes "producer ran" from "value is null".

```powershell
Precondition = @{
    All = @(
        @{ Exists = 'State.GetMailbox.Mailbox' }
        @{ Equals = @{ Path = 'State.GetMailbox.Mailbox.RecipientTypeDetails'; Value = 'UserMailbox' } }
    )
}
```

### Deferred `With` templates

- A `With` string that contains at least one `State` placeholder is **not** resolved at planning time. It stays in
  the plan verbatim (also in the plan export) and is resolved right before the step runs, against `Request` and
  `State` in one pass. Strings without `State` placeholders are resolved at planning time as today.
- Resolving the original string (instead of a partially resolved one) means request values can never inject
  `State` placeholders.
- Planning checks that the `Request` paths of a deferred string exist. The `WithSchema` check of a deferred value is
  skipped at planning time; the key schema is stored in the plan and applied after resolution.
- Pure placeholders keep their type (as today), mixed strings become strings. Only scalar values are allowed.
- A placeholder that resolves to `$null` or a missing value fails the step (`StateReferenceUnresolved`).

The plan step carries:

| Property | Content |
| --- | --- |
| `StateSchema` | The producer's `StateSchema` (or `$null`), used to validate the handler result. |
| `DeferredWith` | One entry per deferred string: `Path` (e.g. `With.Message`), `Segments`, `Schema` (key schema or `$null`). |

## 4. Planning validation

For every `State.*` path in `Precondition` and in deferred `With` templates:

| Code | When |
| --- | --- |
| `StateReferenceNotAllowed` | `State.*` used in `Condition`. |
| `StateReferenceInvalid` | Path has no step name (`State` alone) or the step name is not an identifier. |
| `StateReferenceUnknownStep` | No step with that name runs before the referencing step. `Steps` see earlier `Steps`; `OnFailureSteps` see all `Steps` and earlier `OnFailureSteps`. |
| `StateReferenceAmbiguous` | Referenced from `OnFailureSteps`, and the name exists in both collections. |
| `StateReferenceNotDeclared` | The producer's step type has no `StateSchema`, or `<Key>` is not declared (unless `AllowAdditionalKeys`). |

Paths below `<Key>` are not validated (values such as `Mailbox` come from providers).

## 5. Execution

- After a step completes, the engine stores a data-only copy of its `State` under its name. Retries publish only
  the final, successful result.
- Steps that are `NotApplicable`, `PreconditionSkipped`, `Blocked` or `Failed` publish nothing.
- `OnFailureSteps` see State from completed `Steps` and from earlier completed `OnFailureSteps`.
- `IdLE.StepResult.State` is unchanged. State is not written to events.

## 6. Security

- State is data-only: the engine rejects ScriptBlocks, `PSCredential` and `SecureString` in handler results.
- Templates keep the existing type checks (scalars only, credential types rejected).
- Deferred strings come from the workflow definition only (see 3.).

## 7. Breaking changes

- A handler returning `State` without `StateSchema` in its metadata now fails (`InvalidStepHandlerResult`). Only
  `IdLE.Step.Mailbox.GetInfo` returned State; it declares `StateSchema`.
- `{{State.*}}` in `With` was rejected as a disallowed template root before; it is now valid.

## 8. Implementation plan

1. Catalog: `StateSchema` validation, plan step `StateSchema`, generator output table.
2. Engine: result validation, State store, precondition root, deferred `With` templates.
3. Planning validation of references (codes above).
4. `Mailbox.GetInfo` declares `StateSchema`; example workflow; docs (`steps.md`, `preconditions.md`, `templates.md`).

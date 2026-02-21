---
title: Template Substitution
sidebar_label: Template Substitution
---

# Template Substitution

IdLE supports **template placeholders** in workflow step configuration (`With.*` values).
Placeholders are resolved during plan build (`New-IdlePlan`) before any step runs.

---

## Syntax

A placeholder is written as `{{path}}`, where `path` is a dot-separated property path into the
current lifecycle request:

```powershell
IdentityKey = '{{Request.IdentityKeys.sAMAccountName}}'
DisplayName = '{{Request.DesiredState.GivenName}}'
Message     = 'User {{Request.DesiredState.DisplayName}} is joining.'
```

Multiple placeholders may appear in a single string value.

---

## Allowed roots

For security, only the following path roots are permitted:

| Root | Description |
| ---- | ----------- |
| `Request.DesiredState.*` | Intended target state of the identity |
| `Request.IdentityKeys.*` | Identifiers of the target identity |
| `Request.Changes.*` | Explicit deltas (Mover events) |
| `Request.LifecycleEvent` | Lifecycle event type (e.g. `Joiner`) |
| `Request.CorrelationId` | Stable correlation identifier |
| `Request.Actor` | Originator of the request |
| `Request.Input.*` | Alias for `Request.DesiredState.*` when no `Input` property exists |

Accessing any other root (e.g. `Plan.*`, `Providers.*`) throws a **security error** during plan build.

---

## Pure vs. mixed placeholders

### Pure placeholder

A value that contains **only** a single placeholder (no surrounding text) preserves the resolved
type (bool, int, datetime, guid, string):

```powershell
# Resolves to the actual [bool] value — not the string "True"
Enabled = '{{Request.DesiredState.IsEnabled}}'
```

### Mixed placeholder (string interpolation)

A value that contains text alongside one or more placeholders always produces a **string**:

```powershell
# Always a string result
Message = 'Account for {{Request.DesiredState.DisplayName}} created.'
```

---

## Backslash and special characters

Backslash (`\`) is a **literal character** in template strings and has no special meaning.
This allows Windows-style paths and domain-qualified names without any extra escaping:

```powershell
# \ is kept as-is; only the placeholder is substituted
IdentityKey = 'DOMAIN\{{Request.IdentityKeys.sAMAccountName}}'
# → e.g.  'DOMAIN\jdoe'
```

---

## Escaping a literal `{{`

To include a literal `{{` in the output (not treated as a placeholder), prefix with a backslash
**and** ensure no valid template path follows the opening braces:

```powershell
# \{{ not followed by a valid path+}} → literal {{ in output
Value = 'Literal \{{ braces here'
# → 'Literal {{ braces here'
```

The escape is only applied when `\{{` is **not** immediately followed by a valid path identifier
and closing `}}`. This means the following works without any special escaping:

```powershell
# \ before {{ followed by a valid path — treated as literal \ + resolved template
IdentityKey = 'DOMAIN\{{Request.IdentityKeys.sAMAccountName}}'
# → 'DOMAIN\jdoe'  (not an escape; \ stays, template resolves)
```

Summary:

| Input | Result |
| ----- | ------ |
| `DOMAIN\{{Request.IdentityKeys.sAMAccountName}}` | `DOMAIN\jdoe` — `\` literal, template resolved |
| `Literal \{{ braces here` | `Literal {{ braces here` — `\{{` escaped (no valid path follows) |
| `Literal \{{ and template {{Request.Input.Name}}` | `Literal {{ and template TestName` — escape + template |

---

## Validation

During plan build, IdLE validates every template value:

- **Unbalanced braces** — mismatched `{{`/`}}` pairs throw a syntax error.
- **Invalid path pattern** — paths must use dot-separated identifiers (letters, numbers, underscores). Spaces and special characters are not allowed.
- **Disallowed root** — paths outside the allowlist throw a security error.
- **Null or missing value** — if the resolved value is `null` or the path does not exist, an error is thrown. Ensure the request contains all required values before building the plan.
- **Non-scalar value** — resolving to a hashtable or array is not allowed. Use a scalar property path or flatten the data before creating the request.

---

## See also

- [Walkthrough 1 — Workflow definition](../../use/walkthrough/01-workflow-definition.md)
- [Walkthrough 3 — Plan build](../../use/walkthrough/03-plan-creation.md)
- [Security](../../about/security.md)

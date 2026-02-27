---
title: Template Substitution
sidebar_label: Template Substitution
---

# Template Substitution

Template substitution allows you to reference values from the **planning context** inside step configuration (`With`) values during planning. Conditions and Preconditions use the condition DSL and path resolution and do **not** support `{{...}}` templates.

Templates are **data-only** and safe.  
No ScriptBlocks or dynamic PowerShell expressions are supported.

---

## What is Template Substitution?

Template substitution resolves values from: `Request.*`

It replaces template placeholders with actual values before execution.

Think of template substitution as **value resolution**, not logic execution. \
It simply reads values from the context and inserts them into configuration fields.

---

## ⚠️ Context Resolvers vs Templates vs Conditions vs Preconditions

:::warning Do not confuse these concepts
**[Context Resolvers](./context-resolver.md)** populate `Request.Context.*` during **planning**.  
**Template Substitution** consumes `Plan` / `Request` / `Workflow` values to build strings.  
**[Conditions](./conditions.md)** decide step applicability during **planning** (`NotApplicable`).  
**[Preconditions](./preconditions.md)** guard step behavior during **execution** (`Blocked` / `Fail` / `Continue`).
:::

---

## Resolution Context

Templates can reference:

| Root | Description |
| ---- | ----------- |
| `Request.Intent.*` | Caller-provided action inputs |
| `Request.Context.*` | Read-only associated context (host/resolver-provided) |
| `Request.IdentityKeys.*` | Identifiers of the target identity |
| `Request.LifecycleEvent` | Lifecycle event type (e.g. `Joiner`) |
| `Request.CorrelationId` | Stable correlation identifier |
| `Request.Actor` | Originator of the request |

---

## Example

```powershell
@{
  Name = 'Create UPN'
  Type = 'IdLE.Step.EnsureAttributes'

  With = @{
    UserPrincipalName = '{{Request.IdentityKeys.FirstName}}.{{Request.IdentityKeys.LastName}}@example.com'
  }
}
```

If:

- FirstName = John
- LastName = Doe

The resolved value becomes:

```
John.Doe@example.com
```

---

## Common Patterns

### Pure placeholder resolution

A value containing **only** a single placeholder preserves the resolved type (bool, int, datetime, guid, string):

```powershell
# Resolves to the actual [bool] value, not the string "True"
Enabled = '{{Request.Intent.IsEnabled}}'
```

### Build composite attributes

```powershell
DisplayName = '{{Request.IdentityKeys.FirstName}} {{Request.IdentityKeys.LastName}}'
```

### Include lifecycle event

A value with surrounding text always produces a **string**:

```powershell
Description = 'Provisioned during {{Request.LifecycleEvent}}'
```

### Backslash and special characters

Backslash (`\`) is a **literal character** in template strings and requires no escaping.
Windows-style paths and domain-qualified names work as-is:

```powershell
# \ is kept as-is; only the placeholder is substituted
IdentityKey = 'DOMAIN\{{Request.IdentityKeys.sAMAccountName}}'
# → e.g. 'DOMAIN\jdoe'
```

### Escaping a literal `{{`

To include a literal `{{` in the output, prefix it with `\`. The escape is applied whenever
`\{{` is **not** immediately followed by a valid allowed-root template path and `}}`:

```powershell
# \{{ not followed by a valid path+}} → literal {{ in output
Value = 'Literal \{{ braces here'
# → 'Literal {{ braces here'

# \{{ followed by an invalid/disallowed path → also escaped (literal {{ in output)
Value = '\{{Request.InvalidRoot}}'
# → '{{Request.InvalidRoot}}'
```

Summary of backslash behaviour:

| Input | Result |
| ----- | ------ |
| `DOMAIN\{{Request.IdentityKeys.sAMAccountName}}` | `DOMAIN\jdoe` — `\` literal, valid template resolved |
| `Literal \{{ braces here` | `Literal {{ braces here` — escape applied |
| `\{{Request.InvalidRoot}}` | `{{Request.InvalidRoot}}` — invalid root, escape applied |
| `Literal \{{ and {{Request.Intent.Name}}` | `Literal {{ and TestName` — escape + template |

### Template Validation

During plan build, IdLE validates every template value:

- **Unbalanced braces** — mismatched `{{`/`}}` pairs throw a syntax error.
- **Invalid path** — paths must use dot-separated identifiers (letters, numbers, underscores).
- **Disallowed root** — paths outside the allowlist throw a security error.
- **Null or missing value** — if the resolved path does not exist, an error is thrown.
- **Non-scalar value** — resolving to a hashtable or array is not allowed.

---

## Troubleshooting

### Placeholder not resolved

- Verify the path exists in the request or plan context.
- Ensure correct casing and full path (e.g. `Request.Context.*`).

### Empty value after substitution

- The referenced path may be `$null`.
- Validate the request preparation logic before execution.

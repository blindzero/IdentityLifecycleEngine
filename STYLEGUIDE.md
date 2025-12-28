# IdentityLifecycleEngine (IdLE) Style Guide

This document defines the **coding, documentation, and testing standards**
for **IdentityLifecycleEngine (IdLE)**.

This is the authoritative source for style and best practices.

---

## 1. PowerShell Coding Standards

### 1.1 PowerShell Version

- PowerShell Core **7+ only**

---

### 1.2 Language Rules

- All code, comments, and documentation **must be in English**
- Prefer explicit, readable code

---

### 1.3 Naming

- Verb-Noun for public cmdlets (`New-`, `Test-`, `Invoke-`)
- Singular nouns
- No abbreviations unless well known

---

### 1.4 Formatting

- 4 spaces indentation
- One statement per line
- Curly braces on same line

```powershell
if ($condition) {
    Do-Something
}
```

---

## 2. Public APIs & Functions

### 2.1 Public vs Private

- Public functions must be exported explicitly
- Private helpers must not be exported

---

### 2.2 Error Handling

- Use `throw` for errors
- Do not use `Write-Error` for control flow
- Errors must be actionable

---

## 3. Comment-Based Help (Mandatory)

All public functions MUST include comment-based help.

Required sections:

- `.SYNOPSIS`
- `.DESCRIPTION`
- `.PARAMETER`
- `.EXAMPLE`
- `.OUTPUTS`

---

## 4. Inline Comments

- Explain **why**, not **what**
- Avoid obvious comments

---

## 5. Configuration Rules

- PSD1 only for workflows and metadata
- No PowerShell expressions
- No script blocks
- No dynamic evaluation

---

## 6. Steps

Steps must:

- be idempotent
- produce data-only actions
- never perform authentication
- write only declared `State.*` outputs

---

## 7. Providers

Providers:

- handle all authentication
- use `ExecutionContext.AcquireSession()`
- never assume global state
- must be mockable

---

## 8. State Management

- Replace-at-path semantics (V1)
- No deep merges
- No overwriting other steps' outputs

---

## 9. Testing Standards

### 9.1 Framework

- Pester only

### 9.2 Test Types

- Unit tests (Core)
- Contract tests (Providers)
- Workflow validation tests

---

## 10. Documentation Structure

- `/docs/architecture.md`
- `/docs/domain-model.md`
- `/docs/steps/<StepId>.md`
- `/docs/providers/<Provider>.md`

Documentation must be updated together with code changes.

---

## 11. IDE & Tooling

### 11.1 Recommended IDE

- Visual Studio Code

### 11.2 Extensions

- PowerShell
- EditorConfig
- Markdown All in One

---

## 12. Do's and Don'ts

### Do

- validate early
- write tests
- document decisions

### Don't

- add UI to the engine
- add auth to steps
- hide logic in configuration
- introduce global state

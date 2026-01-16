# IdLE Style Guide

This document defines **coding, documentation, and testing standards**
for **IdentityLifecycleEngine (IdLE)**.
It follows widely accepted **GitHub and PowerShell community conventions**.

---

## General Principles

- Prefer clarity over cleverness
- Fail early and explicitly
- Keep behavior deterministic
- Avoid hidden side effects

---

## PowerShell Standards

### PowerShell Version

- PowerShell Core **7+ only**

---

### Naming Conventions

- Verb-Noun cmdlet naming
- Singular nouns
- Avoid abbreviations
- Only approved Verbs

---

### Formatting

- 4 spaces indentation
- UTF-8, LF
- One statement per line

---

## Public APIs

### Comment-Based Help (Required)

All exported functions must include comment-based help with:

- `.SYNOPSIS`
- `.DESCRIPTION`
- `.PARAMETER`
- `.EXAMPLE`
- `.OUTPUTS`

Public APIs are part of the contract and must remain stable.

---

## Inline Comments

- Explain **why**, not **what**
- Avoid restating obvious code

---

## Configuration Rules

- PSD1 only
- No script blocks
- No PowerShell expressions
- Configuration must be data-only

---

## Steps

Steps must:

- be idempotent
- produce data-only actions
- not perform authentication
- write only declared `State.*` outputs

---

## Providers

Providers:

- handle authentication
- use `ExecutionContext.AcquireAuthSession()`
- must be mockable
- must not assume global state

---

## Testing

- Pester only
- No live system calls in unit tests
- Providers require contract tests

## Quality Gates

IdLE uses static analysis and automated tests to keep the codebase consistent and maintainable.

- **PSScriptAnalyzer** is the required linter for PowerShell code.
  - Repository policy is defined in `PSScriptAnalyzerSettings.psd1` (repo root).
  - Run locally via `pwsh -NoProfile -File ./tools/Invoke-IdleScriptAnalyzer.ps1`.
  - CI publishes analyzer outputs under `artifacts/`.
  - On default-branch runs, CI also uploads SARIF to GitHub Code Scanning.

- **Pester** is the required test framework.
  - Run locally via `pwsh -NoProfile -File ./tools/Invoke-IdlePesterTests.ps1`.
  - CI publishes test results and coverage under `artifacts/`.

---

## Documentation Responsibilities

Documentation *process* lives in **CONTRIBUTING.md**.
This style guide focuses on **in-code documentation rules** (comment-based help, inline comments).

---

## Do's and Don'ts

### Do

- validate early
- write tests
- document decisions
- keep surface small, no private function exports

### Don't

- add UI to the engine
- add auth to steps
- hide logic in config
- introduce global state

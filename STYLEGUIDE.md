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
- use `ExecutionContext.AcquireSession()`
- must be mockable
- must not assume global state

---

## Testing

- Pester only
- No live system calls in unit tests
- Providers require contract tests

---

## Documentation

Documentation must be updated when:

- public APIs change
- workflow behavior changes
- provider auth requirements change

---

## Tooling

### Recommended IDE

- Visual Studio Code

### Extensions

- PowerShell
- EditorConfig
- Markdown All in One

---

## Do's and Don'ts

### Do

- validate early
- write tests
- document decisions

### Don't

- add UI to the engine
- add auth to steps
- hide logic in config
- introduce global state

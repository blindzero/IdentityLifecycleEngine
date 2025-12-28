# Contributing to IdentityLifecycleEngine (IdLE)

Thank you for contributing to **IdentityLifecycleEngine (IdLE)** 🎉  
This document explains **how we work in this repository**.

For detailed coding and documentation rules, see **STYLEGUIDE.md**.

---

## 1. Project Overview

IdLE is a **headless, data-driven Identity Lifecycle (JML) engine** built with PowerShell Core.
The project prioritizes:

- deterministic behavior
- strict validation
- security by design
- long-term maintainability

---

## 2. Repository Structure

```shell
/src
  /IdLE.Core
  /IdLE.Steps.*
  /IdLE.Providers.*
/tests
  /IdLE.Core.Tests
  /IdLE.Steps.Tests
/docs
  architecture.md
STYLEGUIDE.md
CONTRIBUTING.md
README.md
```

---

## 3. Development Workflow

### 3.1 Branching

- `main` – stable
- `feature/<name>`
- `fix/<name>`

### 3.2 Commits

- Small, focused commits
- English commit messages

Format:

```
<area>: <short description>
```

### 3.3 Pull Requests

All changes require a Pull Request.

PRs must include:

- clear description of what and why
- tests for new/changed behavior
- documentation updates if public behavior changes

---

## 4. Definition of Done

A contribution is considered done when:

- tests pass (`Invoke-Pester`)
- strict validation rules are not weakened
- public APIs are documented
- architecture principles are respected
- STYLEGUIDE.md rules are followed

---

## 5. Tooling

- PowerShell Core 7+
- Pester for tests
- Visual Studio Code recommended

---

## 6. Documentation

- Architecture: `docs/architecture.md`
- Coding & documentation rules: **STYLEGUIDE.md**

---

Happy contributing 🚀  
— *IdLE Maintainers*

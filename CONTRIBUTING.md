# Contributing to IdentityLifecycleEngine (IdLE)

Thank you for your interest in contributing to **IdentityLifecycleEngine (IdLE)**! 🎉  
We welcome contributions that improve quality, stability, and maintainability.

This document follows common **GitHub open-source conventions** and explains **how to contribute**.
For detailed coding rules, see **STYLEGUIDE.md**.

---

## Code of Conduct

This project expects respectful and constructive collaboration.
(If a CODE_OF_CONDUCT.md is added, it applies to all contributors.)

---

## How Can I Contribute?

You can contribute by:

- Reporting bugs
- Suggesting enhancements
- Improving documentation
- Submitting pull requests

---

## Reporting Bugs

Please open a GitHub Issue and include:

- a clear and descriptive title
- steps to reproduce
- expected vs. actual behavior
- environment details (PowerShell version, OS)

---

## Suggesting Enhancements

Enhancement proposals should:

- explain the problem being solved
- explain why it fits IdLE’s architecture
- consider backward compatibility

---

## Development Setup

### Prerequisites

- PowerShell Core 7+
- Git
- Visual Studio Code (recommended)

### Clone the Repository

```bash
git clone https://github.com/<org>/IdentityLifecycleEngine.git
```

---

## Development Workflow

### Branching Model

- `main` → stable
- feature branches:
  - `feature/<short-description>`
  - `fix/<short-description>`

---

### Commit Messages

- Use clear, concise English
- One logical change per commit

Recommended format:

```shell
<area>: <short description>
```

Example:

```shell
core: add strict workflow validation
```

---

### Pull Requests

1. Fork the repository (if external contributor)
2. Create a feature branch
3. Make your changes
4. Add or update tests
5. Update documentation if needed
6. Open a Pull Request against `main`

Pull Requests must:

- have a clear description of changes
- reference related issues (if applicable)
- pass all tests
- follow STYLEGUIDE.md

---

## Definition of Done

A contribution is complete when:

- all tests pass
- no architecture rules are violated
- public APIs are documented
- relevant docs are updated

---

## Documentation

- Architecture: `docs/idle-architecture.md`
- Coding & documentation rules: **STYLEGUIDE.md**

---

Thank you for contributing 🚀  
— *IdLE Maintainers*

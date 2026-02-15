# IdentityLifecycleEngine (IdLE)

![IdLE Logo](/docs/assets/logos/idle_logo_flat_white_text_small.png)

[![CI](https://github.com/blindzero/IdentityLifecycleEngine/actions/workflows/ci.yml/badge.svg)](https://github.com/blindzero/IdentityLifecycleEngine/actions/workflows/ci.yml)
[![Latest](https://img.shields.io/github/v/release/blindzero/IdentityLifecycleEngine?sort=semver)](https://github.com/blindzero/IdentityLifecycleEngine/releases?q=prerelease%3Afalse)
[![All Releases](https://img.shields.io/github/v/release/blindzero/IdentityLifecycleEngine?include_prereleases&sort=semver)](https://github.com/blindzero/IdentityLifecycleEngine/releases)

[![PowerShell](https://img.shields.io/badge/PowerShell-7%2B-blue)](#requirements)
[![Pester](https://img.shields.io/badge/Tests-Pester%205-blueviolet)](#testing)
[![License](https://img.shields.io/badge/License-See%20LICENSE-lightgrey)](LICENSE.md)

---

IdLE is a **generic, headless, configuration-driven** lifecycle orchestration engine
for identity and account processes (Joiner / Mover / Leaver), built for **PowerShell 7+**.

The key idea is to **separate intent from implementation**:

- **What** should happen is defined in a **workflow** (data-only configuration).
- **How** it happens is implemented by **steps** and **providers** (pluggable modules).
  - **steps** define, via StepTypes, which provider-agnostic **capabilities** are required to perform a workflow step
  - **providers** register to the core and announce the provided **capabilities** and implement the vendor system specific interface

---

## Why IdLE?

IdLE is a **generic, headless, configuration-driven** lifecycle orchestration engine
for identity and account processes (Joiner / Mover / Leaver), built for **PowerShell 7+**.

The key idea is to **separate intent from implementation**:

- **What** should happen is defined in a **workflow** (data-only configuration).
- **How** it happens is implemented by **steps** and **providers** (pluggable modules).
  - **steps** define, via StepTypes, which provider-agnostic **capabilities** are required to perform a workflow step
  - **providers** register to the core and announce the provided **capabilities** and implement the vendor system specific interface

---

## Key Features

- **Plan → Execute** flow (preview actions before applying them)
- **Joiner / Mover / Leaver** orchestration (and custom lifecycle events)
- **Plugin step model** (idempotent, provider-agnostic)
- **Structured events** for audit/progress (CorrelationId, Actor, step results)

For a complete overview of concepts, see **[About > Concepts](docs/about/concepts.md)**.

---

## Installation

**Quick install:**

```powershell
Install-Module -Name IdLE -Scope CurrentUser
Import-Module IdLE
```

For further installation instructions, requirements, and options, see **[Installation Guide](docs/use/installation.md)**.

---

## How to start

Please refer to the documentation in **["How to use IdLE?"](docs/use/intro-use.md)** for further instructions, on 

1. How to write a workflow
2. Create an identity lifecycle request
3. Plan the IdLE run
4. Invoke & Execute the Plan

---

## IdLE Demo

Run the end-to-end demo (Plan → Execute):

```powershell
pwsh -File .\examples\Invoke-IdleDemo.ps1 -All
```

The demo shows:

- creating a lifecycle request
- building a deterministic plan from a workflow definition (`.psd1`)
- executing the plan using built-in steps and a mock provider

By default, the demo runs **Mock workflows** that work out-of-the-box without external systems.
The examples folder also includes **Template workflows** that demonstrate real-world scenarios with Active Directory, Entra ID, Exchange Online but these require the corresponding infrastructure and provider modules.

---

## Documentation

The documentation is also available at our project site: [https://blindzero.github.io/IdentityLifecycleEngine](https://blindzero.github.io/IdentityLifecycleEngine)

Start here:

- [docs/about/intro.md](docs/about/intro.md) – About IdLE
- [docs/use/intro-use.md](docs/use/intro-use.md) – How to use IdLE
- [docs/reference/intro-reference.md](docs/reference/intro-reference.md) - The authoritative IdLE reference

---

## Contributing

PRs welcome. Please see [CONTRIBUTING.md](CONTRIBUTING.md) and [STYLEGUIDE.md](STYLEGUIDE.md)

---

## Roadmap

See Github [Issues](https://github.com/blindzero/IdentityLifecycleEngine/issues) and [Milestones](https://github.com/blindzero/IdentityLifecycleEngine/milestones) for our roadmap.

---

## License

See the [LICENSE.md](LICENSE.md) file.

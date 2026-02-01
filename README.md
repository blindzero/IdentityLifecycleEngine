# IdentityLifecycleEngine (IdLE)

![IdLE Logo](/docs/assets/idle_logo_flat_white_text_small.png)

[![CI](https://github.com/blindzero/IdentityLifecycleEngine/actions/workflows/ci.yml/badge.svg)](https://github.com/blindzero/IdentityLifecycleEngine/actions/workflows/ci.yml)
[![Latest](https://img.shields.io/github/v/release/blindzero/IdentityLifecycleEngine?sort=semver)](https://github.com/blindzero/IdentityLifecycleEngine/releases?q=prerelease%3Afalse)
[![All Releases](https://img.shields.io/github/v/release/blindzero/IdentityLifecycleEngine?include_prereleases&sort=semver)](https://github.com/blindzero/IdentityLifecycleEngine/releases)

[![PowerShell](https://img.shields.io/badge/PowerShell-7%2B-blue)](#requirements)
[![Pester](https://img.shields.io/badge/Tests-Pester%205-blueviolet)](#testing)
[![License](https://img.shields.io/badge/License-See%20LICENSE-lightgrey)](LICENSE.md)

**IdLE** is a **generic, headless, configurable Identity or Account Lifecycle / JML (Joiner–Mover–Leaver) orchestration engine** built for **PowerShell**.

It helps you standardize identity lifecycle processes across environments by separating:

- **what** should happen (workflow definition)
- from **how** it happens (providers)

---

## Why IdLE?

Identity lifecycle automation tends to become:

- tightly coupled to one system or one environment
- hard to test
- hard to change (logic baked into scripts)

IdLE aims to be:

- **portable** (run anywhere PowerShell 7 runs)
- **modular** (steps + providers are swappable)
- **testable** (Pester-friendly; mock providers)
- **configuration-driven** (workflows as data)
- **extensible** (add custom steps and providers)

For a complete overview of concepts, see **[About > Concepts](docs/about/concepts.md)**.

---

## Key Features

- **Plan → Execute** flow (preview actions before applying them)
- **Joiner / Mover / Leaver** orchestration (and custom lifecycle events)
- **Plugin step model** (idempotent, provider-agnostic)
- **Structured events** for audit/progress (CorrelationId, Actor, step results)

---

## Installation

**Quick install:**

```powershell
Install-Module -Name IdLE -Scope CurrentUser
Import-Module IdLE
```

For detailed installation instructions, requirements, and import options, see **[Installation Guide](docs/use/installation.md)**.

---

## Quickstart

Run the end-to-end demo (Plan → Execute):

```powershell
pwsh -File .\examples\Invoke-IdleDemo.ps1
```

The demo shows:

- creating a lifecycle request
- building a deterministic plan from a workflow definition (`.psd1`)
- executing the plan using built-in steps and a mock provider

By default, the demo runs **Mock workflows** that work out-of-the-box without external systems. The examples folder also includes **Live workflows** that demonstrate real-world scenarios with Active Directory and Entra ID, but these require the corresponding infrastructure and provider modules.

The execution result buffers all emitted events in `result.Events`. Hosts can optionally stream events live
by providing `-EventSink` as an object implementing `WriteEvent(event)`.

---

## Documentation

The documentation is also available at our project site: [https://blindzero.github.io/IdentityLifecycleEngine](https://blindzero.github.io/IdentityLifecycleEngine)

Start here:

- [docs/index.md](docs/index.md) – Documentation map
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

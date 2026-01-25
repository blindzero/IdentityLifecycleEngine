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
- from **how** it happens (providers/adapters)

For a complete overview of concepts, architecture, and why IdLE exists, see **[Overview: Concept](docs/overview/concept.md)**.

---

## Key Features

- **Plan → Execute** flow (preview actions before applying them)
- **Configuration-driven** (workflows as data, no code in config)
- **Modular** (steps + providers are swappable)
- **Portable** (PowerShell 7+, runs anywhere)
- **Testable** (Pester-friendly; mock providers)

---

## Installation

**Quick install:**

```powershell
Install-Module -Name IdLE -Scope CurrentUser
Import-Module IdLE
```

For detailed installation instructions, requirements, and import options, see **[Installation Guide](docs/getting-started/installation.md)**.

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

Next steps:

- Documentation entry point: `docs/index.md`
- Workflow samples: `examples/workflows/` (organized by category: mock, live, templates)
- Repository demo: `examples/Invoke-IdleDemo.ps1`
- Pester tests: `tests/`

---

## Documentation

Start here:

- `docs/index.md` – documentation map
- `docs/getting-started/quickstart.md` – plan → execute walkthrough
- `docs/advanced/architecture.md` – architecture and principles
- `docs/usage/workflows.md` – workflow schema and validation

---

## Contributing

PRs welcome. Please see [CONTRIBUTING.md](CONTRIBUTING.md) and [STYLEGUIDE.md](STYLEGUIDE.md)

---

## Roadmap

See Github [Issues](https://github.com/blindzero/IdentityLifecycleEngine/issues) and [Milestones](https://github.com/blindzero/IdentityLifecycleEngine/milestones) for our roadmap.

---

## License

See the [LICENSE.md](LICENSE.md) file.

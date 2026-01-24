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

---

## Features

- **Joiner / Mover / Leaver** orchestration (and custom life cycle events)
- **Plan → Execute** flow (preview actions before applying them)
- **Plugin step model** (`Test` / `Invoke`, optional `Rollback` later)
- **Provider/Adapter pattern** (directory, SaaS, REST, file/mock…)
- **Structured events** for audit/progress (CorrelationId, Actor, step results)
- **Idempotent execution** (steps can be written to converge state)

---

## Requirements

- PowerShell **7.x** (`pwsh`)
- Pester **5.7.1** (for tests)
- PSScriptAnalyzer **1.24.0** (for tests)

---

## Installation

### Install from PowerShell Gallery (recommended)

```powershell
Install-Module -Name IdLE -Scope CurrentUser
Import-Module IdLE
```

> The `IdLE` meta-module loads the bundled nested modules (engine, built-in steps, and the mock provider used by examples)
> from within the installed package.

### Install from source (contributors / development)

```powershell
git clone https://github.com/blindzero/IdentityLifecycleEngine
cd IdentityLifecycleEngine

# Import meta module
Import-Module ./src/IdLE/IdLE.psd1 -Force
```

#### What gets loaded when you import `IdLE`

`IdLE` is the **batteries-included** entrypoint. Importing it loads:

- `IdLE.Core` — the workflow engine (step-agnostic)
- `IdLE.Steps.Common` — first-party built-in steps (e.g. `IdLE.Step.EmitEvent`, `IdLE.Step.EnsureAttribute`)

Built-in steps are **available to the engine by default**, but are intentionally **not exported into the global session state**.
This keeps your PowerShell session clean while still allowing workflows to reference built-in steps by `Step.Type`.

If you want to call step functions directly (e.g. `Invoke-IdleStepEmitEvent`) you can explicitly import the step pack:

```powershell
Import-Module ./src/IdLE.Steps.Common/IdLE.Steps.Common.psd1 -Force
```

#### Engine-only import

Advanced hosts can import the engine without any step packs:

```powershell
Import-Module ./src/IdLE.Core/IdLE.Core.psd1 -Force
```

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

# IdentityLifecycleEngine (IdLE)

![IdLE Logo](/assets/images/logo.png)

[![CI](https://github.com/blindzero/IdentityLifecycleEngine/actions/workflows/ci.yml/badge.svg)](https://github.com/blindzero/IdentityLifecycleEngine/actions/workflows/ci.yml)
[![Latest](https://img.shields.io/github/v/release/blindzero/IdentityLifecycleEngine?sort=semver)](https://github.com/blindzero/IdentityLifecycleEngine/releases/latest)
[![Pre-Release](https://img.shields.io/github/v/release/blindzero/IdentityLifecycleEngine?include_prereleases&sort=semver)](https://github.com/blindzero/IdentityLifecycleEngine/releases)

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
- Pester **5.x** (for tests)

---

## Installation

### Option A — Clone & import locally (current)

```powershell
git clone https://github.com/blindzero/IdentityLifecycleEngine
cd IdentityLifecycleEngine

Import-Module ./src/IdLE/IdLE.psd1 -Force
```

### Option B — PowerShell Gallery (planned)

Once published:

```powershell
Install-Module IdLE
```

---

## Quickstart

Run the end-to-end demo (Plan → Execute):

```powershell
pwsh -File .\examples\run-demo.ps1
```

The demo shows:

- creating a lifecycle request
- building a deterministic plan from a workflow definition (`.psd1`)
- executing the plan using a host-provided step registry

The execution result buffers all emitted events in `result.Events`. Hosts can optionally stream events live
by providing `-EventSink` as an object implementing `WriteEvent(event)`.

Next steps:

- Documentation entry point: `docs/index.md`
- Workflow samples: `examples/workflows/`
- Repository demo: `examples/run-demo.ps1`
- Pester tests: `tests/`

---

## Documentation

Start here:

- `docs/index.md` – documentation map
- `docs/getting-started/quickstart.md` – plan → execute walkthrough
- `docs/advanced/architecture.md` – architecture and principles
- `docs/usage/workflows.md` – workflow schema and validation

Project docs:

- Contributing: `CONTRIBUTING.md`
- Style guide: `STYLEGUIDE.md`

---

## Contributing

PRs welcome. Please see [CONTRIBUTING.md](CONTRIBUTING.md)

- Keep the core **host-agnostic**
- Prefer **configuration** over hardcoding logic
- Aim for **idempotent** steps
- Keep **in-code comments/docs in English**

---

## Roadmap

See Github [Issues](https://github.com/blindzero/IdentityLifecycleEngine/issues) and [Milestones](https://github.com/blindzero/IdentityLifecycleEngine/milestones) for our roadmap.

---

## License

See the [LICENSE.md](LICENSE.md) file.

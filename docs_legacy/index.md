# IdentityLifecycleEngine (IdLE) - Documentation

![IdLE Logo](/assets/idle_logo_flat_white_text_small.png)

Welcome to the documentation for **IdentityLifecycleEngine (IdLE)**.

IdLE is a **generic, headless, configuration-driven** lifecycle orchestration engine
for identity and account processes (Joiner / Mover / Leaver) built for **PowerShell 7+**.

---

## User Documentation

For admins, operators, and workflow authors:

### Getting Started

- [Installation](getting-started/installation.md) — Install and import guide (requirements, import options)
- [Quickstart](getting-started/quickstart.md) — Run the demo and understand Plan → Execute flow

### Usage

- [Workflows](usage/workflows.md) — Define lifecycle workflows
- [Steps](usage/steps.md) — Use and configure steps
- [Providers](usage/providers.md) — Provider aliases and injection

### Overview

- [Concept](overview/concept.md) — What is IdLE and why does it exist

### Reference

- [Cmdlet Reference](reference/cmdlets.md) — Public cmdlets and usage
- [Step Catalog](reference/steps.md) — Built-in step reference (generated)
- [Configuration](reference/configuration.md) — Configuration schema reference
- [Events and Observability](reference/events-and-observability.md) — Event structure and streaming
- [Providers and Contracts](reference/providers-and-contracts.md) — Provider responsibilities and contracts

### Provider Guides

- [Active Directory Provider](reference/providers/provider-ad.md)
- [Entra ID Provider](reference/providers/provider-entraID.md)

---

## Developer Documentation

For contributors, extenders, and maintainers:

### Contributing

- [CONTRIBUTING.md](../CONTRIBUTING.md) — Contribution workflow, PR guidelines, quality gates
- [STYLEGUIDE.md](../STYLEGUIDE.md) — Code style and documentation rules
- [AGENTS.md](../AGENTS.md) — Agent operating manual

### Advanced Topics

- [Architecture](advanced/architecture.md) — Design principles and decisions
- [Security](advanced/security.md) — Trust boundaries and threat model
- [Extensibility](advanced/extensibility.md) — Add steps and providers
- [Provider Capabilities](advanced/provider-capabilities.md) — Capability system and validation
- [Testing](advanced/testing.md) — Test strategy and tooling
- [Releasing](advanced/releases.md) — Maintainer release process

### Specifications

Specifications are **normative contracts** (machine-readable formats / stable interfaces)
used between IdLE and its hosts.

- [Plan export (JSON)](specs/plan-export.md)

---

## Examples

- [Examples README](../examples/README.md) — Runnable examples and demo workflows

---

## Quick Links

- [Project README](../README.md) — Repository landing page
- [GitHub Issues](https://github.com/blindzero/IdentityLifecycleEngine/issues)
- [GitHub Releases](https://github.com/blindzero/IdentityLifecycleEngine/releases)

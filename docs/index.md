# IdentityLifecycleEngine (IdLE) - Documentation

![IdLE Logo](/assets/logos/idle_logo_flat_white_text_small.png)

Welcome to the documentation for **IdentityLifecycleEngine (IdLE)**.

IdLE is a **generic, headless, configuration-driven** lifecycle orchestration engine
for identity and account processes (Joiner / Mover / Leaver) built for **PowerShell 7+**.

> Prefer our docs website at https://blindzero.github.io/IdentityLifecycleEngine

---

## About IdLE

Learn the basics [about IdLE](about/intro.md)

- [Concepts](about/concepts.md) - What are the basic concepts of IdLE and how it works in general
- [Architecture](about/architecture.md) - Design principles and decisions
- [Security](about/security.md) - Trust boundaries and threat model

## Use IdLE

Learn how to [use IdLE](use/intro.md) as an operator or admin, e.g. for workflow authoring.

- [Quickstart](use/quickstart.md) - Run the demo and understand Plan → Execute flow
- [Installation](use/installation.md) - Install and import guide (requirements, import options)
- [Configuration](use/configuration.md) - Configuration schema reference
- [Workflows](use/workflows.md) - Define lifecycle workflows
- [Steps](use/steps.md) - Use and configure steps
- [Providers](use/providers.md) - Provider aliases and injection
- [Plan Export](use/plan-export.md) - How to use the Plan Exporter (JSON)

## Extend IdLE

Learn how to [extend IdLE](extend/intro.md) as a developer.

- [Extensibility](extend/extensibility.md) - General extensibility concept of IdLE
- [Events](extend/events.md) - Eventing at IdLE to be used in your extensions
- [Providers](extend/providers.md) - How to build your own custom providers

## Reference

The [authoritative reference](reference/intro.md) for IdLE components.

- [Cmdlets](reference/cmdlets.md) - Public cmdlets and usage
- [Step Catalog](reference/steps.md) - Built-in step reference (generated)
- [Capabilities](reference/capabilities.md) - The capabilities catalog

## Workflow Examples

- [Workflow Examples](../examples/README.md) - Runnable examples and demo workflows

### Provider Reference

- [Active Directory Provider](reference/providers/provider-ad.md)
- [Entra ID Provider](reference/providers/provider-entraID.md)

### Specifications

Specifications are **normative contracts** (machine-readable formats / stable interfaces)
used between IdLE and its hosts.

- [Plan export (JSON)](reference/specs/plan-export.md) - The JSON specification of the Plan export file

---

## Developer Documentation

For contributors, extenders, and maintainers:

- [Testing](develop/testing.md) - Test strategy and tooling
- [Releasing](develop/releases.md) - Maintainer release process

- [CONTRIBUTING.md](../CONTRIBUTING.md) - Contribution workflow, PR guidelines, quality gates
- [STYLEGUIDE.md](../STYLEGUIDE.md) - Code style and documentation rules
- [AGENTS.md](../AGENTS.md) - Agent operating manual

---

## Quick Links

- [Project Website](https://blindzero.github.io/IdentityLifecycleEngine)
- [Project README](../README.md) - Repository landing page
- [GitHub Issues](https://github.com/blindzero/IdentityLifecycleEngine/issues)
- [GitHub Releases](https://github.com/blindzero/IdentityLifecycleEngine/releases)

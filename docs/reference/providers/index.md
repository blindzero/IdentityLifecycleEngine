---
title: Providers Reference
sidebar_label: Providers
---

# Provider Reference

> Entry page for provider reference. This section is **reference-only**: what a provider implements, how to configure it, and which contracts/capabilities it exposes.

---

## Built-in / first-party providers

- **Active Directory (AD)** — Identity operations against on-prem AD via the AD provider module. → `./provider-ad.md`
- **Entra ID** — Identity operations against Microsoft Entra ID via Microsoft Graph. → `./provider-entraID.md`
- **Exchange Online** — Messaging / mailbox related operations against Exchange Online. → `./provider-ExchangeOnline.md`
- **DirectorySync.EntraConnect** — Directory synchronization provider for Entra Connect / sync-cycle related operations. → `./provider-directorysync-EntraConnect.md`
- **Mock** — In-memory / file-backed provider for tests and local development without live systems. → `./provider-mock.md`

---

## Choosing a provider

- Match the **capabilities required by your steps** to the provider’s `GetCapabilities()` output.
- Providers handle authentication/session acquisition via `Context.AcquireAuthSession(...)` (host-controlled).
- In workflows, steps select a provider by **alias** (defaults to `Identity` if omitted).

Related:

- [Capabilities Reference](../capabilities.md)
- [Provider fundamentals (concept)](../../about/concepts.md#providers)
- [Use Providers](../../use/providers.md)

---

## Authoring a provider (for developers)

- Minimal checklist:
  - Implement provider contracts (only what you need)
  - Advertise deterministic capabilities (`GetCapabilities()`)
  - Acquire sessions via host context (no prompts inside providers)
  - Add unit tests + contract tests (no live calls in CI)

Related:

- [Extensibility](../../extend/extensibility.md)
- Testing: `../advanced/testing.md`
- [Security considerations](../../about/security.md)

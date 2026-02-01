---
title: Providers Reference
sidebar_label: Providers
---

> Entry page for provider reference. This section is **reference-only**: what a provider implements, how to configure it, and which contracts/capabilities it exposes.

---

## Built-in / first-party providers

- **[Active Directory (AD)](providers/provider-ad.md)** — Identity operations against on-prem AD via the AD provider module
- **[Entra ID](providers/provider-entraID.md)** — Identity operations against Microsoft Entra ID via Microsoft Graph
- **[Exchange Online](providers/provider-exchangeonline.md)** — Messaging / mailbox related operations against Exchange Online
- **[DirectorySync.EntraConnect](providers/provider-directorysync-entraconnect.md)** — Directory synchronization provider for Entra Connect / sync-cycle related operations
- **[Mock Provider](providers/provider-mock.md)** — In-memory / file-backed provider for tests and local development without live systems

---

## Choosing a provider

- Match the **capabilities required by your steps** to the provider’s `GetCapabilities()` output.
- Providers handle authentication/session acquisition via `Context.AcquireAuthSession(...)` (host-controlled).
- In workflows, steps select a provider by **alias** (defaults to `Identity` if omitted).

Related:

- [Capabilities Reference](capabilities.md)
- [Provider fundamentals (concept)](../about/concepts.md#providers)
- [Use Providers](../use/providers.md)

---

## Authoring a provider (for developers)

- Minimal checklist:
  - Implement provider contracts (only what you need)
  - Advertise deterministic capabilities (`GetCapabilities()`)
  - Acquire sessions via host context (no prompts inside providers)
  - Add unit tests + contract tests (no live calls in CI)

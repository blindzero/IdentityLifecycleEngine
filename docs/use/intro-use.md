---
title: Use IdLE
sidebar_label: Use IdLE
---

This section is the **hands-on guide** for running IdLE in real environments:

- define **workflows** (data-only)
- create **requests**
- build **plans** (validation + template resolution)
- **invoke** plans (execution + events)
- provide **providers** and (if required) **authentication** from your host

:::info
IdLE is not a “click tool”. The primary interfaces are workflow files plus a small set of public cmdlets.
Reference pages are the single source of truth for schemas and cmdlet details.
:::

---

## Start here

1. [Installation](installation.md)
2. [Quick Start](quickstart.md) — first successful run (mock provider, safe)
3. **Walkthrough** — the full lifecycle, step by step:
   - [Workflow definition](walkthrough/01-workflow-definition.md)
   - [Request creation](walkthrough/02-request-creation.md)
   - [Create Plan](walkthrough/03-plan-creation.md)
   - [Invoke & interpret results](walkthrough/04-invoke-results.md)
   - [Providers & authentication](walkthrough/05-providers-authentication.md) (host responsibility)

---

## Use topics

- [Workflows](workflows.md) — how workflow files are structured and validated
- [Providers](providers.md) — provider mapping and authentication patterns
- [Plan Export](plan-export.md) — export plans for review, CI artifacts, and audit

---

## When to use other sections

- If you want the **big picture** (responsibilities, trust boundaries, architecture): see [Concepts](../about/concepts.md)
- If you want to **extend IdLE** (write steps, providers, host integrations): see [Extend](../extend/intro-extend.md)
- If you need **specification-level details**: see [Reference](../reference/intro-reference.md)

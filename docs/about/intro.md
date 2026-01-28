---
title: About IdLE
sidebar_label: Introduction
---

# IdentityLifecycleEngine (IdLE)

![IdLE Logo](/assets/idle_logo_flat_white_text_small.png)

## Introduction

IdLE is a **generic, headless, configuration-driven** lifecycle orchestration engine
for identity and account processes (Joiner / Mover / Leaver), built for **PowerShell 7+**.

The key idea is to **separate intent from implementation**:

- **What** should happen is defined in a **workflow** (data-only configuration).
- **How** it happens is implemented by **steps** and **providers** (pluggable modules).

---

## Why IdLE exists

Identity lifecycle automation often turns into long scripts that are:

- tightly coupled to one environment
- hard to test
- hard to change safely

IdLE aims to be:

- **portable** run in different environments with PowerShell 7+ without a hard dependency on a specific host or UI
- **configuration-driven** workflows are defined as data, not code.
- **modular** a small core and pluggable providers and steps.
- **testable** deterministic planning, mockable providers, and strong contracts.

---

## Key Features

- **Joiner / Mover / Leaver** orchestration (and custom lifecycle events)
- **Plan → Execute** flow (preview actions before applying them)
- **Plugin step model** (`Test` / `Invoke`, optional `Rollback` later)
- **Provider/Adapter pattern** (directory, SaaS, REST, file/mock…)
- **Structured events** for audit/progress (CorrelationId, Actor, step results)
- **Idempotent execution** (steps can be written to converge state)

---

## Where to go next

- [Concepts](concepts.md): more details on the core concepts of IdLE.
- [Use](../use/intro.md): install IdLE, run workflows, export plans, troubleshoot.
- [Extend](../extend/intro.md): implement providers and steps, integrate with secrets and events.
- [Reference](../reference/intro.md): cmdlets, steps, capabilities, and specifications.

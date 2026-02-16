---
title: About IdLE
sidebar_label: Introduction
---

# IdentityLifecycleEngine (IdLE)

![IdLE Logo](/assets/idle_logo_flat_white_text_small.png)

## Introduction

IdLE (Identity Lifecycle Engine) is a **generic, configurable orchestration framework** for identity lifecycle processes
(Joiner / Mover / Leaver and similar cases), built for **PowerShell 7+**.

---

## Why IdLE exists

JML (joiner/mover/leavers) processes are

- error prone, especially if performed manually
- time consuming and therefore
- quite annoying for operators

Self-made identity lifecycle automation often turns into long scripts that are:

- tightly coupled to one environment
- hard to test
- hard to change safely

Identity Management Systems (IdMS) on the other side are either complex or expensive (or both of it) and then often do not care about supplementary systems that also need to be covered within the workflows.

---

## Start using IdLE

- If you want to run IdLE now: start with [Quick Start](../use/quickstart).
- If you want a guided path: follow the [Walkthrough](../use/walkthrough/01-workflow-definition).
- If you want the architecture and responsibility model: read [Concepts](./concepts).

---

## Key ideas

- **Workflows** are data-only `.psd1` files describing what to do.
- A **Request** captures intent + input data.
- A **Plan** is the validated, resolved execution contract.
- **Invoke** executes the plan and emits structured events.
- **Providers** implement system-specific behavior and authentication.

IdLE is designed to be:

- **portable** run in different environments with PowerShell 7+ without a hard dependency on a specific host or UI
- **configuration-driven** workflows are defined as data, not code.
- **modular** a small core and pluggable providers and steps that even support **extending** with your own custom add-ons.
- **testable** deterministic planning, mockable providers, and strong contracts.

:::info
IdLE is **headless**. Your host (script, CI job, service) provides providers and authentication.
Workflows and requests remain data-only.
:::

---

## Next

- [How to use IdLE?](../use/intro-use.md)
  - [Installation](../use/installation.md)
  - [QuickStart](../use/quickstart.md)
  - [Walkthrough - Step 1: Workflow Definition](../use/walkthrough/01-workflow-definition.md)
- [Reference](../reference/intro-reference.md)

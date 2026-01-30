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
  - While **steps** define by StepTypes, which provider-agnostic **capabilities** are required to perform a workflow step
  - **providers** register to the core and announce the provided **capabilities** and implement the vendor system specific interface

---

## Why IdLE exists

JML (joiner/mover/leavers) processes are

- error prune, especially if performed manually
- time consuming and therefore
- quite annoying for operators

Identity lifecycle automation often turns into long scripts that are:

- tightly coupled to one environment
- hard to test
- hard to change safely

Identity Management Systems (IdMS) on the other side are whether complex or expensive (or both of it) and then often do not care about supplementary systems that also need to be covered within the workflows.

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

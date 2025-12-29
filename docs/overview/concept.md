# Overview

IdLE (IdentityLifecycleEngine) is a **generic orchestration framework** for identity lifecycle automation.

The key idea is to **separate intent from implementation**:

- **What** should happen is defined in a **workflow** (data-only configuration).
- **How** it happens is implemented by **steps** and **providers** (pluggable modules).

## Why IdLE exists

Identity lifecycle automation often turns into long scripts that are:

- tightly coupled to one environment
- hard to test
- hard to change safely

IdLE aims to be:

- **portable** (PowerShell 7 runs on many platforms)
- **modular** (steps and providers are swappable)
- **testable** (Pester-friendly, mock providers)
- **configuration-driven** (workflows as data)

## Core concepts

### Request

A **LifecycleRequest** represents the business intent (for example: Joiner, Mover, Leaver).
It is the input to planning.

### Plan

A **LifecyclePlan** is created deterministically from:

- request
- workflow definition
- step catalog / step registry

The plan is previewable and auditable.

### Execute

Execution runs **only the plan** (no re-planning). This supports:

- approvals
- repeatability
- deterministic audits

## Non-goals (V1)

IdLE.Core stays headless and avoids responsibilities that belong to a host application:

- no UI framework
- no interactive prompts
- no authentication flows inside steps
- no dynamic code execution from configuration

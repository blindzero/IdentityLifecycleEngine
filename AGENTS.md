# AGENTS.md

This repository welcomes contributions from both humans and automated agents.

Use this document as the **default operating manual** for any agent (AI assistant, code generator, refactoring bot, CI helper)
working in the repo.

> If this file conflicts with any other repo document, follow the more specific rule (e.g., STYLEGUIDE.md for code style).

---

## 1. Project intent (read first)

**IdentityLifecycleEngine (IdLE)** is a **generic, headless, configuration-driven** identity lifecycle orchestration engine
(Joiner / Mover / Leaver) built for **PowerShell 7+**.

Core principles:

- Portable, modular, testable, highly configurable
- **Plan → Execute** separation (deterministic planning, repeatable execution)
- Workflow configuration is **data-only** (no script blocks / no dynamic expressions)
- Engine stays **host-agnostic** (no UI / no service-host coupling)

Authoritative docs:

- `README.md` (high-level)
- `docs/index.md` (documentation entry point)
- `docs/about/security.md` (trust boundaries)
- `docs/reference/capabilities.md` (Capability rules)
- `docs/extend/providers.md` (Provider contracts)
- `docs/extend/steps.md` (Step metadata/capabilities usage)

---

## 2. How to behave as an agent

### 2.1 No assumptions

- If something is unclear, **ask targeted questions**.
- Prefer a sensible default proposal, but **explicitly label it** as a default.

### 2.2 One change-set at a time

- Keep PRs focused: one issue / one theme.
- Avoid drive-by refactors unless the issue is specifically about refactoring.
- Minimal changes, no unrelated refactors.

### 2.3 Determinism over cleverness

- Prefer explicit validation and deterministic behavior.
- Avoid “magic” behavior, hidden fallbacks, or implicit global state.

---

## 3. Coding standards (PowerShell)

Follow `STYLEGUIDE.md` for the full rule set. In short:

- PowerShell **Core 7+**
- Use **approved PowerShell verbs** (Verb-Noun)
- 4 spaces indentation, UTF-8, LF
- Public cmdlets require **comment-based help** (`.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER`, `.EXAMPLE`, `.OUTPUTS`)
- Inline comments should explain **why**, not what

### 3.1 Public vs. Private

- Keep a clean separation between Public and Private functions.
- Treat exported commands as stable contracts.

### 3.2 Configuration is data-only (no code in config)

- Workflow definitions (PSD1) must be **data-only**:
  - No `ScriptBlock`
  - No dynamic PowerShell expressions
- Validate early and fail with actionable errors.

---

## 4. Architectural constraints

### 4.1 Headless core

The engine (`IdLE.Core`) must **not** depend on:

- UI frameworks
- interactive prompts
- service hosts / web servers

### 4.2 Steps vs. Providers

- **Steps**: convergence logic, idempotent intent, no authentication
- **Providers**: system adapters, handle authentication and external calls
- Steps should only write to declared `State.*` outputs.
- Authentication model (no prompting):
  - Providers must not prompt interactively or implement ad-hoc login flows.
  - Hosts MUST provide an `AuthSessionBroker`, and steps/providers MUST acquire auth sessions via `Context.AcquireAuthSession(...)` rather than receiving raw credentials directly.
  - Do not pass secrets or credential objects via provider options or workflow configuration; provider options must remain data-only (no ScriptBlocks, no executable objects).

#### 4.2.1 Capability naming convention

- New work MUST use the IdLE. capability namespace (e.g., IdLE.Identity.Read, IdLE.Identity.Attribute.Ensure, IdLE.Entitlement.Grant).
- Do not introduce new un-namespaced capabilities (e.g., Identity.Read) in new modules.
- If legacy capability names exist, treat them as deprecated aliases and document migration behavior explicitly in the relevant issue/PR.

### 4.3 Eventing

Use the single event contract:

- `Context.EventSink.WriteEvent(Type, Message, StepName, Data)`
- This is the runtime contract used by steps/providers through the execution context.
- External event sinks (host implementations) must follow the guidance in `docs/extend/events.md` (object-based event payload), but the engine-facing API remains `Context.EventSink.WriteEvent(...)`.

Do not introduce alternative eventing APIs unless explicitly planned and documented.

---

## 5. Testing expectations

Follow `docs/develop/testing.md` and `CONTRIBUTING.md`.

- Use **Pester** for tests.
- Unit tests must not call live systems.
- Provider implementations require **provider contract tests**.
- Providers should be tested against the existing provider contract test suites and must avoid live system dependencies in CI.
- If a provider wraps external cmdlets/APIs, introduce an internal adapter layer so unit tests can mock behavior without calling the real system.

**PR rule:** New behavior should include tests. Bug fixes must include a regression test.

---

## 6. Documentation responsibilities

- Keep docs short and linkable.
- Update docs when changing contracts, configuration schema, public cmdlets, step behavior, or provider contracts.

### 6.1 Generated references

The cmdlet and step references under `docs/reference/` are generated.
Do **not** edit generated files by hand—regenerate via the repository tools as documented in `CONTRIBUTING.md`.

---

## 7. Security and trust boundaries

Follow `docs/about/security.md`.

- Treat workflow definitions and lifecycle requests as **untrusted inputs**
- Reject executable objects in untrusted inputs (e.g., ScriptBlocks)
- Treat step registry, providers, and external event sinks as **trusted extension points**, but validate their shapes
- Authentication material (credentials/tokens) is considered secret input and must not be logged or emitted in events; redact at output boundaries as documented in `docs/about/security.md`

---

## 8. PR checklist (Definition of Done)

Before proposing or finalizing a PR, ensure:

- [ ] Changes are scoped to a single issue/theme
- [ ] All tests pass (`Invoke-Pester -Path ./tests`)
- [ ] Public APIs have comment-based help
- [ ] Docs updated where needed (`README.md`, `docs/`, `examples/`)
- [ ] Generated docs regenerated if required (`docs/reference/*`)
- [ ] No concept or extensibility rules violated (`docs/about/concepts.md`, `docs/extend/extensibility.md`)
- [ ] No security boundary regressions (`docs/about/security.md`)
- [ ] Security vulnerabilities addressed (see `SECURITY.md` for reporting)

---

## 9. Conflict resolution

If any guidance in this document conflicts with other repository documents:

- The more specific document takes precedence
- If the conflict is unclear, open an issue to resolve it

Document precedence (from most to least specific):

1. Domain-specific docs (`docs/extend/*`, `docs/develop/*`, `docs/about/*`)
2. Policy docs at repo root (`STYLEGUIDE.md`, `CONTRIBUTING.md`, `SECURITY.md`)
3. This document (`AGENTS.md`)

---

## 10. Where to put new guidance for agents

- General, cross-cutting agent rules → `AGENTS.md` (repo root)
- Code style details → `STYLEGUIDE.md`
- Contributor workflow and DoD → `CONTRIBUTING.md`
- Concept decisions → `docs/about/concepts.md`
- Extensibility decisions → `docs/extend/extensibility.md`
- Security boundaries → `docs/about/security.md`
- Testing guidance → `docs/develop/testing.md`
- Capability rules → `docs/reference/capabilities.md`
- Event patterns → `docs/extend/events.md`
- Provider contracts → `docs/extend/providers.md`
- Step metadata → `docs/extend/steps.md`

---

## 11. When in doubt

Prefer:

- clarity over cleverness
- explicit validation over implicit behavior
- small PRs over large rewrites
- documentation + tests as part of the same change

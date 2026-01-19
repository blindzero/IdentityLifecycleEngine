# Repository instructions for GitHub Copilot

This repository is **IdentityLifecycleEngine (IdLE)**: a **generic, headless, configuration-driven identity lifecycle / JML orchestration engine** for **PowerShell 7+**.

Use these instructions when suggesting or generating changes in this repo (chat, code review, coding agent).

## Primary sources of truth

- Agent operating manual: `AGENTS.md`
- Coding and documentation rules: `STYLEGUIDE.md`
- Contributor workflow + Definition of Done: `CONTRIBUTING.md`
- Architecture: `docs/advanced/architecture.md`
- Security + trust boundaries: `docs/advanced/security.md`

If anything in this file conflicts with those, the more specific document wins.

## Core constraints (do not violate)

- **PowerShell 7+ only.**
- **Headless core:** `IdLE.Core` must not depend on UI frameworks, interactive prompts, or service/web hosts.
- **Plan → Execute separation:** planning is deterministic; execution runs the plan as-built.
- **Configuration is data-only:** workflow PSD1 files must not contain ScriptBlocks or executable objects.
- **Steps vs providers:**
  - Steps are idempotent intent/convergence logic and must not do authentication.
  - Providers handle external system access and authentication via `Context.AcquireAuthSession(...)`.

## Style and quality gates

- Use **approved PowerShell verbs** and **Verb-Noun** naming.
- Use **4 spaces indentation**, UTF-8, LF.
- Public commands must have **comment-based help** (`.SYNOPSIS/.DESCRIPTION/.PARAMETER/.EXAMPLE/.OUTPUTS`).
- Avoid drive-by refactors. Keep PRs focused on **one issue/theme**.
- Add/adjust **Pester tests** for new behavior or bug fixes.
- Run repo scripts:
  - `./tools/Invoke-IdlePesterTests.ps1`
  - `./tools/Invoke-IdleScriptAnalyzer.ps1`

## Documentation rules

- Do not edit generated references under `docs/reference/` by hand.
  - **Always regenerate** after changing public cmdlets or step implementations:
    - `./tools/Generate-IdleCmdletReference.ps1` - after cmdlet/help changes
    - `./tools/Generate-IdleStepReference.ps1` - after step changes
  - See `CONTRIBUTING.md` for complete instructions.
  - CI will fail if generated docs are out of date.

## Git / PR conventions

- Use small, reviewable commits; one logical change per commit.
- Prefer branch names like `issues/<issueNumber>-<sanitizedTitle>` for human work.

> Note: **Copilot coding agent** is restricted to creating/pushing to branches that start with `copilot/` on GitHub.com.

# CLAUDE.md

@AGENTS.md

## Claude-specific notes

`AGENTS.md` (imported above) is the operating manual for all agents. This file only adds what is specific to Claude Code.

- **PR review criteria** live in the project skill `.claude/skills/idle-pr-review/SKILL.md`.
  The same skill is used locally and by the CI review gate (`.github/workflows/claude-review.yml`).
- **Quality checks** (run from the repository root):
  - `pwsh -NoProfile -File ./tools/Invoke-IdlePesterTests.ps1`
  - `pwsh -NoProfile -File ./tools/Invoke-IdleScriptAnalyzer.ps1`
- **Generated references** under `docs/reference/` are never edited by hand. Regenerate them with
  `./tools/Generate-IdleCmdletReference.ps1` and `./tools/Generate-IdleStepReference.ps1` (see `CONTRIBUTING.md`).
- **Branch names** for issue work: `issues/<issueNumber>-<sanitizedTitle>`.
- On pull requests, CI restores `.claude/` and `CLAUDE.md` from the base branch. Changes to these files only take
  effect for reviews after they are merged.

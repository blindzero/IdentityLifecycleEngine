# Contributing to IdentityLifecycleEngine (IdLE)

Thank you for your interest in contributing to **IdentityLifecycleEngine (IdLE)**! 🎉  
We welcome contributions that improve quality, stability, and maintainability.

This document follows common **GitHub open-source conventions** and explains **how to contribute**.
For detailed coding rules, see **STYLEGUIDE.md**.

---

## Code of Conduct

This project expects respectful and constructive collaboration.
(If a CODE_OF_CONDUCT.md is added, it applies to all contributors.)

---

## How Can I Contribute?

You can contribute by:

- Reporting bugs
- Suggesting enhancements
- Improving documentation
- Submitting pull requests

---

## Reporting Bugs

Please open a GitHub Issue and include:

- a clear and descriptive title
- steps to reproduce
- expected vs. actual behavior
- environment details (PowerShell version, OS)

---

## Suggesting Enhancements

Enhancement proposals should:

- explain the problem being solved
- explain why it fits IdLE’s architecture
- consider backward compatibility

---

## Development Setup

### Prerequisites

- PowerShell Core 7+
- Git
- Visual Studio Code (recommended)

### Recommended IDE & extensions (optional)

- Visual Studio Code
- Extensions:
  - PowerShell
  - EditorConfig
  - Markdown All in One

### Clone the Repository

```bash
git clone https://github.com/blindzero/IdentityLifecycleEngine.git
```

---

## Development Workflow

### Branching Model

- `main` → stable
- feature branches:
  - `feature/<short-description>`
  - `fix/<short-description>`

---

### Commit Messages

- Use clear, concise English
- One logical change per commit

Recommended format:

```shell
<area>: <short description>
```

Example:

```shell
core: add strict workflow validation
```

---

### Pull Requests

1. Fork the repository (if external contributor)
2. Create a feature branch
3. Make your changes
4. Add or update tests
5. Update documentation if needed
6. Open a Pull Request against `main`

Pull Requests must:

- have a clear description of changes
- reference related issues (if applicable)
- pass all tests
- follow STYLEGUIDE.md

---

## Definition of Done

A contribution is complete when:

- all tests pass (`pwsh -NoProfile -File ./tools/Invoke-IdlePesterTests.ps1`)
- static analysis passes (`pwsh -NoProfile -File ./tools/Invoke-IdleScriptAnalyzer.ps1`)
- no architecture rules are violated (see `docs/advanced/architecture.md`)
- public APIs are documented (comment-based help for exported functions)
- documentation is updated where required:
  - README.md (only high-level overview + pointers)
  - docs/ (usage/concepts/examples)
  - provider/step module READMEs if behavior/auth changes

## Local quality checks

IdLE provides canonical scripts under `tools/` so you can reproduce the same checks locally that CI runs.

### Run tests (Pester)

Run the test suite:

- `pwsh -NoProfile -File ./tools/Invoke-IdlePesterTests.ps1`

To generate CI-like artifacts (test results + coverage) under `artifacts/`:

- `pwsh -NoProfile -File ./tools/Invoke-IdlePesterTests.ps1 -CI`

Outputs:

- `artifacts/test-results.xml` (NUnitXml)
- `artifacts/coverage.xml` (coverage report)

### Run static analysis (PSScriptAnalyzer)

Run PSScriptAnalyzer using the repository settings:

- `pwsh -NoProfile -File ./tools/Invoke-IdleScriptAnalyzer.ps1`

To generate CI-like artifacts under `artifacts/` (including SARIF for GitHub Code Scanning):

- `pwsh -NoProfile -File ./tools/Invoke-IdleScriptAnalyzer.ps1 -CI`

Outputs:

- `artifacts/pssa-results.json` (summary)
- `artifacts/pssa-results.sarif` (SARIF)

The rule set is defined in `PSScriptAnalyzerSettings.psd1` at the repository root.
The runner pins tool versions for deterministic CI results; update pins intentionally and document the change in the PR.

> Note: `artifacts/` is a build output folder and should not be committed.

---

## Generated cmdlet reference (platyPS)

IdLE maintains a generated cmdlet reference under:

- `docs/reference/cmdlets.md` (index page)
- `docs/reference/cmdlets/*.md` (one file per cmdlet)

These files are generated from comment-based help in the PowerShell source. **Do not edit the generated files by hand.**
Instead, update the comment-based help of the relevant public function/cmdlet and regenerate the reference.

### platyPS version pinning

The cmdlet reference is generated using **platyPS**.

To ensure deterministic output across platforms and CI environments, the CI pipeline
**pins a specific platyPS version**.

Do not upgrade platyPS casually.

If you intentionally want to upgrade platyPS:

1. Update the pinned version in the CI workflow.
2. Regenerate the cmdlet reference locally using the same version.
3. Commit the regenerated files under `docs/reference/cmdlets/`.
4. Verify that CI passes without diffs.

This avoids documentation drift caused by formatting or template changes between platyPS versions.

### When to regenerate

Regenerate the cmdlet reference when you change any of the following for exported/public commands:

- Add/remove/rename a public cmdlet/function
- Add/remove/rename parameters (including parameter sets)
- Change comment-based help: synopsis/description/parameters/examples

### How to regenerate locally

From the repository root:

```powershell
pwsh ./tools/Generate-IdleCmdletReference.ps1
```

If `platyPS` is not installed yet, you can install it automatically (requires internet access):

```powershell
pwsh ./tools/Generate-IdleCmdletReference.ps1 -InstallPlatyPS
```

Commit the changed files under `docs/reference/` as part of the same PR that introduced the cmdlet/help changes.

### CI enforcement (required status check)

The CI pipeline verifies that the generated cmdlet reference is up to date. If you change public cmdlets or their
comment-based help and forget to regenerate the docs, the workflow **"Verify cmdlet reference is up to date"** will fail.

To fix a failing PR:

1. Run the generator locally from the repo root:

   ```powershell
   pwsh ./tools/Generate-IdleCmdletReference.ps1
   ```

   If needed (first time only):

   ```powershell
   pwsh ./tools/Generate-IdleCmdletReference.ps1 -InstallPlatyPS
   ```

2. Commit the updated files under `docs/reference/` and push to your branch.

Repository maintainers should configure branch protection so that required status checks include this workflow. This ensures
generated docs cannot drift from the exported cmdlets.

## Generated step reference

IdLE maintains a generated step reference under:

- `docs/reference/steps.md`

The file is generated from step implementations in `IdLE.Steps.*` and their comment-based help.
**Do not edit the generated file by hand.** Update the step help/source and regenerate the reference.

### When to regenerate

Regenerate the step reference when you change any of the following:

- Add/remove/rename a step implementation (`Invoke-IdleStep*`)
- Change step behavior that affects documented inputs (With.* keys), contracts, idempotency, or emitted events
- Update comment-based help of step implementations

### How to regenerate locally

From the repository root:

```powershell
pwsh ./tools/Generate-IdleStepReference.ps1
```

Commit the updated `docs/reference/steps.md` as part of the same PR that introduced the step changes.

### CI enforcement (required status check)

The CI pipeline verifies that the generated step reference is up to date. If you change steps and forget to regenerate the docs,
the workflow **"Verify step reference is up to date"** will fail.

To fix a failing PR:

1. Run the generator locally:

   ```powershell
   pwsh ./tools/Generate-IdleStepReference.ps1
   ```

2. Commit the updated `docs/reference/steps.md` and push to your branch.

Repository maintainers should configure branch protection so that required status checks include this workflow.

## Documentation

Keep docs short and linkable:

- README.md: landing page (what/why + 30s quickstart + links)
- docs/: architecture, usage, examples (small focused pages)
- examples/: runnable scripts and workflow samples

Key links:

- Docs map: `docs/00-index.md`
- Architecture: `docs/advanced/architecture.md`
- Examples: `docs/02-examples.md`
- Coding & in-code documentation rules: `STYLEGUIDE.md`

---

Thank you for contributing 🚀  
— *IdLE Maintainers*

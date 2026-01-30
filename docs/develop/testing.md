# Testing

IdLE is designed to be testable in isolation. Tests should be deterministic, fast, and runnable on any machine (local or CI) without requiring live systems.

## Requirements

- Pester **5.7.1+** (for running tests, optional)
- PSScriptAnalyzer **1.24.0+** (for running static analysis, optional)

## Test folder structure

Tests are organized by domain under `tests/`:

- **`tests/Core/`** — Core engine functionality (plan creation, execution, conditions, workflows, capabilities, redaction)
- **`tests/Steps/`** — Step implementations (built-in steps like EnsureEntitlement, Mailbox operations, DirectorySync)
- **`tests/Providers/`** — Provider implementations (AD, EntraID, ExchangeOnline, Mock, DirectorySync)
- **`tests/Packaging/`** — Module manifests, public API surface, release artifacts
- **`tests/Examples/`** — Workflow samples and demo smoke tests
- **`tests/fixtures/`** — Test data and workflow definitions for tests
- **`tests/_testHelpers.ps1`** — Shared test infrastructure (single entry point for all tests)

All test files follow the naming convention `*.Tests.ps1` and are automatically discovered by Pester.

Test helper functions are split by domain:
- `tests/_testHelpers.ps1` (main entry point, imports domain helpers)
- `tests/Steps/_testHelpers.Steps.ps1` (step-specific helpers)
- `tests/Providers/_testHelpers.Providers.ps1` (provider-specific helpers)

## Running tests locally

Use the canonical test runner:

```powershell
pwsh -NoProfile -File ./tools/Invoke-IdlePesterTests.ps1
```

Enable coverage (optional):

```powershell
pwsh -NoProfile -File ./tools/Invoke-IdlePesterTests.ps1 -EnableCoverage
```

If you want a specific coverage format:

```powershell
pwsh -NoProfile -File ./tools/Invoke-IdlePesterTests.ps1 -EnableCoverage -CoverageOutputFormat Cobertura
```

## Unit tests

Unit tests should:

- use **Pester**
- use **mock providers**
- avoid live system calls
- prefer explicit, committed fixtures over writing ad-hoc temporary files

## Provider contract tests

Provider contract tests verify that an implementation matches the expected contract.

They should:

- test the *contract behavior* (inputs/outputs, error handling, capability surface)
- run against **mock/file providers** by default
- run against real providers only as an explicit, opt-in scenario (separate pipeline / environment)

## CI artifacts

The CI pipeline produces test artifacts under the `artifacts/` folder and uploads them.

Expected outputs:

- `artifacts/test-results.xml` (JUnitXml test results)
- `artifacts/coverage.xml` (code coverage report; format depends on configuration)

In addition to uploading these artifacts, CI automatically publishes:

- **Test results** as a GitHub Check (visible in PR checks and workflow runs)
- **Code coverage** as a GitHub Check with inline PR comments
- **Coverage summary** in the workflow run summary

This allows reviewers to see test failures and coverage directly in GitHub's UI without downloading artifacts.

## Static analysis

IdLE uses **PSScriptAnalyzer** as a CI quality gate to enforce baseline style and correctness rules.

Local run:

```powershell
pwsh -NoProfile -File ./tools/Invoke-IdleScriptAnalyzer.ps1
```

The analyzer uses the repository settings file:

- `PSScriptAnalyzerSettings.psd1` (repo root)

In CI, PSScriptAnalyzer emits machine-readable artifacts under `artifacts/` (JSON and optional SARIF) and can publish SARIF findings to GitHub Code Scanning on default-branch runs.

## Documentation consistency checks

In addition to code tests and static analysis, IdLE runs a deterministic documentation audit to keep the docs tree consistent
with the Docusaurus website configuration.

Run locally:

```powershell
pwsh -NoProfile -File ./tools/Test-DocsConsistency.ps1
```

What it checks:

- **Orphan docs**: Markdown files under `docs/` that are not referenced from `website/sidebars.js`
- **Broken internal links**:
  - `/docs/...` routes must resolve to a file under `docs/`
  - relative Markdown links must point to an existing file
- **MDX risks** in `.md` / `.mdx` files: common constructs that may accidentally trigger MDX parsing
- **Long pages**: a line-count warning threshold (defaults to 350 lines)

Outputs:

- `artifacts/docs-audit.json` (machine-readable report for CI artifacts)

CI behavior:

- By default, the script fails (non-zero exit code) on:
  - orphan docs
  - link issues
  - MDX risks
- Long pages are treated as warnings by default (configurable via `-FailOnLongPages`)

When running on GitHub Actions, the script also emits GitHub workflow annotations (errors/warnings) so issues show up
directly in the PR UI.

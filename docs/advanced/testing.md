# Testing

IdLE is designed to be testable in isolation. Tests should be deterministic, fast, and runnable on any machine (local or CI) without requiring live systems.

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

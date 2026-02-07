---
title: Releases
sidebar_labels: Releases
---

# Releasing IdLE

This document describes the **maintainer** release process for IdLE.

IdLE currently ships release artifacts in two channels:

- **GitHub Releases** (always)  
- **PowerShell Gallery** (stable releases only, guarded by environment approval)

Pre-release tags are **GitHub-only** (no PowerShell Gallery publish).

## Principles and guardrails

- **No direct commits to `main`.** Release prep is done via a Pull Request.
- Tags must be created on the intended `main` commit.  
- The Release workflow validates that the tag version matches the module manifest versions (fail-fast).
- Publishing to PowerShell Gallery is protected via a GitHub **Environment** (`psgallery-prod`) and requires approval.
- A local end-to-end publish test runs in CI (publishes to a local repository, then installs/imports the module).

## Release workflow safety gates

The Release workflow enforces additional guardrails for tagged releases:

- **Tag must point to `origin/main` HEAD** (fail-fast).
- **CI must be green for the tag commit** (`ci.yml` must have a successful run for the same SHA).
- **Tag base version must match all shipped module manifests**.

These checks prevent "broken" releases (e.g., tagging the wrong commit or forgetting the version bump).

## Versioning policy

IdLE follows [Semantic Versioning](https://semver.org/):

- **MAJOR** (breaking): Incompatible API changes
- **MINOR** (feature): Backward-compatible functionality additions
- **PATCH** (fix): Backward-compatible bug fixes

### Multi-Module Versioning Strategy

Starting with version 1.0, IdLE uses a **synchronized versioning strategy** across all published modules:

- All modules (`IdLE`, `IdLE.Core`, `IdLE.Steps.Common`, providers, and step modules) share the **same version number**
- Version bumps are **synchronized** across all modules in each release
- This ensures predictable dependency resolution and simplifies version management

**Rationale:**
- Simplifies dependency declarations (all modules have matching versions)
- Reduces complexity in release automation
- Provides clear "release cohesion" — all modules in a release are tested together
- Easier for users to understand which modules are compatible

**Example:**
```
Release v1.2.0:
- IdLE                    1.2.0
- IdLE.Core               1.2.0
- IdLE.Steps.Common       1.2.0
- IdLE.Provider.AD        1.2.0
- IdLE.Provider.EntraID   1.2.0
- (all other modules)     1.2.0
```

**Tool Support:**
The repository tool `Set-IdleModuleVersion.ps1` updates all module manifests synchronously to ensure consistency.

### What Constitutes a Breaking Change

The following are **breaking changes** and require a new major version:

- Removing a supported command
- Renaming a supported command
- Removing a parameter
- Renaming a parameter
- Changing a parameter from optional to mandatory
- Changing a parameter's type in an incompatible way
- Removing fields from workflow/request/plan contracts
- Renaming fields in workflow/request/plan contracts

The following are **non-breaking** (allowed in minor/patch versions):

- Adding a new command
- Adding a new parameter (must be optional with a sensible default)
- Changing exact error message strings
- Adding new output properties (output types are coarse-grained)
- Internal implementation changes

### Deprecation Mechanism

Deprecated supported cmdlets/parameters **MUST** emit a `Write-Warning` on use:

**Format**:
```
DEPRECATED: <Item> is deprecated in <version> and will be removed in <major_version>.
Use <replacement> instead.
```

**Example**:
```powershell
Write-Warning "DEPRECATED: Parameter 'OldName' is deprecated in v1.2 and will be removed in v2.0. Use 'NewName' instead."
```

**Timeline**: Deprecated features will be supported for **at least one minor version** before removal in the next major version.

**Example timeline**:
- Deprecated in v1.2 → Removed in v2.0
- Deprecated in v1.8 → Removed in v2.0

### Stable tags

Stable releases use tags in the form:

- `vMAJOR.MINOR.PATCH` (example: `v1.2.0`)

For stable releases, all shipped module manifests must have:

- `ModuleVersion = MAJOR.MINOR.PATCH`

### Pre-release tags (GitHub only)

Pre-releases use tags in the form:

- `vMAJOR.MINOR.PATCH-&lt;label&gt;` (example: `v1.2.0-preview.1`, `v1.2.0-rc.1`)

**Important:** the module manifests still use the *base* version:

- `ModuleVersion = MAJOR.MINOR.PATCH`

That means: to cut `v1.2.4-preview.1`, the manifests must already be bumped to `1.2.4`.  
(The Release workflow extracts the base version and validates it against all module manifests.)

Pre-release tags do **not** publish to PowerShell Gallery.

## Release preparation (always via PR)

1. Create a branch for the release preparation (for example: `release/v1.2.0`).
2. Bump all shipped module versions using the repository tool:

   ```powershell
   pwsh -NoProfile -File ./tools/Set-IdleModuleVersion.ps1 -TargetVersion 1.2.0
   ```

3. Run quality checks locally:

   - Pester tests:

     ```powershell
     pwsh -NoProfile -File ./tools/Invoke-IdlePesterTests.ps1
     ```

   - Static analysis (PSScriptAnalyzer):

     ```powershell
     pwsh -NoProfile -File ./tools/Invoke-IdleScriptAnalyzer.ps1
     ```

4. Commit and push the changes.
5. Open a Pull Request to `main` and wait for CI to pass.
6. Merge the Pull Request.

> Tip: Avoid editing module manifests manually. Use `Set-IdleModuleVersion.ps1` to reduce mistakes and keep changes deterministic.

## Dry-run (no GitHub Release)

Use this to validate that the artifact builds correctly without creating a GitHub Release and without tagging.

1. Start the workflow manually: **Actions → Release → Run workflow**
2. Select the branch to run on (typically `main`).
3. Provide a non-SemVer tag label (to avoid version validation), for example:

   - `dryrun-YYYYMMDD`

4. Ensure `publish_release` and `publish_psgallery` are **false**.

The workflow uploads an expanded artifact as a workflow run artifact.

## Cut a GitHub pre-release (tagged)

Use this when you want a GitHub-only preview build.

1. Ensure the manifests are bumped to the target base version (PR merged), e.g. `1.2.4`.
2. Create an annotated tag on the `main` merge commit:

   ```bash
   git checkout main
   git pull --ff-only

   git tag -a v1.2.4-preview.1 -m "IdLE v1.2.4-preview.1"
   git push origin v1.2.4-preview.1
   ```

3. The Release workflow will:
   - Build the ZIP artifact
   - Create a GitHub Release marked as **pre-release**
   - Run the local publish test
   - Skip PowerShell Gallery publishing

If you need another preview, repeat with `preview.2`, etc. (no version bump required as long as base version stays the same).

## Cut a stable release (GitHub Release + optional PSGallery publish)

1. Ensure the manifests are bumped to the target version (PR merged), e.g. `1.2.0`.
2. Create an annotated tag:

   ```bash
   git checkout main
   git pull --ff-only

   # Create an annotated tag (recommended)
   git tag -a v1.2.0 -m "IdLE v1.2.0"

   # Push the tag to trigger the Release workflow
   git push origin v1.2.0
   ```

3. The Release workflow will:
   - Build the ZIP artifact
   - Create a GitHub Release (not marked as pre-release)
   - Run the local publish test
   - Run the PSGallery job **only** for stable tags and only after environment approval

### PowerShell Gallery publishing

IdLE is published to the PowerShell Gallery as **multiple separate modules** (multi-module distribution):

- **IdLE** (meta-module) — Declares `IdLE.Core` and `IdLE.Steps.Common` as `RequiredModules`
- **IdLE.Core** — Workflow engine (no IdLE dependencies)
- **IdLE.Steps.Common** — Built-in steps (requires `IdLE.Core`)
- **IdLE.Provider.\*** — Provider modules (each published separately, typically require `IdLE.Core`)
- **IdLE.Steps.\*** — Optional step modules (published separately, require `IdLE.Core` and/or `IdLE.Steps.Common`)

**Publishing Order:**

Modules are published in **dependency order** to ensure dependencies exist before dependent modules:

1. `IdLE.Core` (no IdLE dependencies)
2. `IdLE.Steps.Common` (depends on Core)
3. `IdLE` (depends on Core + Steps.Common)
4. All providers and optional step modules

The publish order is defined in `tools/ModulePublishOrder.psd1` and used by the release workflow.

**Workflow Behavior:**

- On tag pushes matching `v*`, the workflow publishes all modules to PSGallery in dependency order.
- A 30-second delay is added between publishes to allow PSGallery processing time.
- For manual runs (`workflow_dispatch`), publishing is only performed when **publish_psgallery** is set to `true`.

### Package staging

The workflow does not publish directly from the repository `src/` layout. Instead it stages publishable packages using:

- `tools/New-IdleModulePackage.ps1 -Mode MultiModule`

**Packaging modes:**

1. **Bundled Mode** (`-Mode Bundled`, default):
   - Creates a single package with nested modules under `Modules/`
   - Output: `artifacts/IdLE/`
   - Used for legacy distribution (GitHub releases, zip archives)

2. **MultiModule Mode** (`-Mode MultiModule`):
   - Creates separate packages for each module
   - Output: `artifacts/modules/<ModuleName>/`
   - Used for PowerShell Gallery publishing
   - **Manifest transformation for IdLE:**
     - Converts `NestedModules` with relative paths → `RequiredModules` with module names
     - Removes `ScriptsToProcess` entry
     - Removes `IdLE.Init.ps1` file (not needed in published packages)

**Why transform manifests?**

- **Source manifests** use `NestedModules` with relative paths to support direct import from repository/zip: `Import-Module ./src/IdLE/IdLE.psd1`
- **Published manifests** use `RequiredModules` with module names for standard PowerShell dependency resolution when installed via `Install-Module`

This dual-manifest approach ensures:
- ✅ Contributors can work directly from repository source
- ✅ Published modules follow PowerShell best practices
- ✅ No `$env:PSModulePath` configuration required for either scenario

For details on the architecture, see **[Installation Guide](../use/installation.md#multi-module-architecture)**.

## Versioning and naming

- Use `vMAJOR.MINOR.PATCH` tags (for example `v1.2.0`).
- Pre-releases are allowed (for example `v1.2.0-rc.1`). They should be tested via the dry-run path first.
- Avoid deleting and reusing tags.

## Troubleshooting

### The workflow failed but no artifact exists

- Check the step **Verify artifact exists** in the workflow logs.
- Run the packaging script locally in list-only mode to inspect the file list:

```powershell
pwsh -NoProfile -File ./tools/New-IdleReleaseArtifact.ps1 -Tag v1.2.0-test -ListOnly
```

### Tag was pushed but the workflow fails with a version mismatch

This means the tag version does not match one or more module manifests.

Fix by:

1. Bumping versions via `Set-IdleModuleVersion.ps1`
2. Merging the PR
3. Creating a new tag on the correct commit

### I want to “redo” a release

With immutable releases enabled, treat published releases as immutable.

Preferred approach:

1. Fix the issue on `main`.
2. Cut a new version tag (for example `v1.2.1`).

### The PSGallery publish job is blocked

This is expected when `psgallery-prod` requires approval.  
Approve the deployment in the workflow run UI, and ensure `PSGALLERY_API_KEY` is set in the environment.

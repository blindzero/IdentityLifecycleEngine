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

## Versioning policy

### Stable tags

Stable releases use tags in the form:

- `vMAJOR.MINOR.PATCH` (example: `v0.7.0`)

For stable releases, all shipped module manifests must have:

- `ModuleVersion = MAJOR.MINOR.PATCH`

### Pre-release tags (GitHub only)

Pre-releases use tags in the form:

- `vMAJOR.MINOR.PATCH-<label>` (example: `v0.7.0-preview.1`, `v0.7.0-rc.1`)

**Important:** the module manifests still use the *base* version:

- `ModuleVersion = MAJOR.MINOR.PATCH`

That means: to cut `v0.7.4-preview.1`, the manifests must already be bumped to `0.7.4`.  
(The Release workflow extracts the base version and validates it against all module manifests.)

Pre-release tags do **not** publish to PowerShell Gallery.

## Release preparation (always via PR)

1. Create a branch for the release preparation (for example: `release/v0.7.0`).
2. Bump all shipped module versions using the repository tool:

   ```powershell
   pwsh -NoProfile -File ./tools/Set-IdleModuleVersion.ps1 -TargetVersion 0.7.0
   ```

3. Run tests:

   ```powershell
   pwsh -NoProfile -File ./tools/run-tests.ps1
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

1. Ensure the manifests are bumped to the target base version (PR merged), e.g. `0.7.4`.
2. Create an annotated tag on the `main` merge commit:

   ```bash
   git checkout main
   git pull --ff-only

   git tag -a v0.7.4-preview.1 -m "IdLE v0.7.4-preview.1"
   git push origin v0.7.4-preview.1
   ```

3. The Release workflow will:
   - Build the ZIP artifact
   - Create a GitHub Release marked as **pre-release**
   - Run the local publish test
   - Skip PowerShell Gallery publishing

If you need another preview, repeat with `preview.2`, etc. (no version bump required as long as base version stays the same).

## Cut a stable release (GitHub Release + optional PSGallery publish)

1. Ensure the manifests are bumped to the target version (PR merged), e.g. `0.7.0`.
2. Create an annotated tag:

   ```bash
   git checkout main
   git pull --ff-only

   # Create an annotated tag (recommended)
   git tag -a v0.7.0 -m "IdLE v0.7.0"

   # Push the tag to trigger the Release workflow
   git push origin v0.7.0
   ```

3. The Release workflow will:
   - Build the ZIP artifact
   - Create a GitHub Release (not marked as pre-release)
   - Run the local publish test
   - Run the PSGallery job **only** for stable tags and only after environment approval

### PowerShell Gallery publishing

IdLE is published to the PowerShell Gallery as a **single package** named `IdLE`.

- On tag pushes matching `v*`, the workflow publishes to PSGallery automatically.
- For manual runs (`workflow_dispatch`), publishing is only performed when **publish_psgallery** is set to `true`.

### Package staging

The workflow does not publish directly from the repository `src/` layout. Instead it stages a publishable, self-contained
package into:

- `artifacts/IdLE`

Staging is performed by:

- `tools/New-IdleModulePackage.ps1`

This script copies the `IdLE` meta-module and required nested modules into a local `Modules/` folder and patches the staged
`IdLE.psd1` so `NestedModules` use in-package relative paths (e.g. `./Modules/IdLE.Core/IdLE.Core.psd1`).

> This approach avoids repository restructuring while ensuring that `Install-Module IdLE` + `Import-Module IdLE` works
> after installation.

## Versioning and naming

- Use `vMAJOR.MINOR.PATCH` tags (for example `v0.7.0`).
- Pre-releases are allowed (for example `v0.7.0-rc.1`). They should be tested via the dry-run path first.
- Avoid deleting and reusing tags.

## Troubleshooting

### The workflow failed but no artifact exists

- Check the step **Verify artifact exists** in the workflow logs.
- Run the packaging script locally in list-only mode to inspect the file list:

```powershell
pwsh -NoProfile -File ./tools/New-IdleReleaseArtifact.ps1 -Tag v0.7.0-test -ListOnly
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
2. Cut a new version tag (for example `v0.7.1`).

### The PSGallery publish job is blocked

This is expected when `psgallery-prod` requires approval.  
Approve the deployment in the workflow run UI, and ensure `PSGALLERY_API_KEY` is set in the environment.
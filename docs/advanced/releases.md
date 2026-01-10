# Releasing IdLE

This document describes how maintainers cut a release using the GitHub Actions workflow.

> This is part of the **advanced** documentation because it is maintainer-focused and describes repository
> operations (tags, GitHub Releases, release artifacts) rather than end-user usage.

## Prerequisites

- You have write permissions to the repository.
- CI is green on `main`.
- The repository uses **immutable releases** (recommended). Once a release is published, its assets and tag should be treated as write-once.

## Dry-run (no GitHub Release)

Use this to validate release packaging without creating a GitHub Release.

Important notes:

- The manual run must be executed from a ref that **contains** the workflow (for example `main` or a feature branch).
  Older tags (for example `v0.6.0`) may not include the `workflow_dispatch` trigger and therefore cannot be used for manual runs.
- The `tag` input is used for **naming** the artifact and does **not** need to exist as a git tag.
- For dry-runs, the workflow uploads the **expanded folder contents** as an artifact to avoid a ZIP-in-ZIP experience.

Steps:

1. Go to **GitHub → Actions → Release**.
2. Click **Run workflow**.
3. **Use workflow from**: select `main` (or a feature branch that contains the workflow).
4. Provide a test tag in the input (for example `v0.7.0-test`).
5. Leave **publish_release** unchecked / `false`.
6. When the workflow completes, download the artifact from the **Artifacts** section of the run and inspect the contents.

This verifies:

- deterministic packaging
- expected include/exclude rules
- the artifact can be produced on a clean runner

## Cut a release (published GitHub Release)

Releases are created from **annotated tags** matching `v*` (for example `v0.7.0`).

From a clean working tree on `main`:

```powershell
git checkout main
git pull --ff-only

# Create an annotated tag (recommended)
git tag -a v0.7.0 -m "IdLE v0.7.0"

# Push the tag to trigger the Release workflow
git push origin v0.7.0
```

What happens next:

1. The **Release** workflow runs on the tag.
2. A deterministic ZIP artifact is created.
3. A GitHub Release is created for the tag, with auto-generated release notes.
4. The ZIP is uploaded as a release asset.

## PowerShell Gallery publishing

IdLE is published to the PowerShell Gallery as a **single package** named `IdLE`.

- On tag pushes matching `v*`, the workflow publishes to PSGallery automatically.
- For manual runs (`workflow_dispatch`), publishing is only performed when **publish_psgallery** is set to `true`.

### PSGallery API key

Publishing requires a repository secret:

- **Name:** `PSGALLERY_API_KEY`
- **Value:** a PowerShell Gallery API key with permission to publish the `IdLE` module.

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

### I want to “redo” a release

With immutable releases enabled, treat published releases as immutable.

Preferred approach:

1. Fix the issue on `main`.
2. Cut a new version tag (for example `v0.7.1`).

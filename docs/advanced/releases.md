# Releasing IdLE

This document describes how maintainers cut a release using the GitHub Actions workflow.

## Prerequisites

- You have write permissions to the repository.
- CI is green on `main`.
- The repository uses **immutable releases** (recommended). Once a release is published, its assets and tag should be treated as write-once.

## Dry-run (no GitHub Release)

Use this to validate the release packaging without creating a GitHub Release.

1. Go to **GitHub → Actions → Release**.
2. Click **Run workflow**.
3. Provide a test tag (for example `v0.7.0-test`).
4. Leave **publish_release** unchecked / `false`.
5. When the workflow completes, download the ZIP from the **Artifacts** section of the run.

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

## Versioning and naming

- Use `vMAJOR.MINOR.PATCH` tags (for example `v0.7.0`).
- Pre-releases are allowed (for example `v0.7.0-rc.1`). They should be tested via the dry-run path first.

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

Avoid deleting and reusing tags.

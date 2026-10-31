---
name: idle-pr-review
description: Review an IdLE pull request or local change set against the project's architecture, security and Definition of Done rules. Classifies findings by severity and produces a PASS/BLOCK verdict. Use when asked to review a PR, a branch, or the current diff in this repository.
---

# IdLE PR review

This skill defines **how** an IdLE change is reviewed and **how findings are classified**.
The rules themselves live in the repository documents below; this skill does not restate them.
It also does not define how results are delivered (inline comments, terminal output); the caller decides that.

## Review procedure

1. Determine the change set (PR diff or local diff against `main`) and the linked issue, if any.
2. Read `AGENTS.md` in full. It is the baseline for every review.
3. Based on what the change touches, read the matching documents from the table below **before** judging the change.
4. Read every changed file in full context, not only the diff hunks.
5. Check the change against the rules in those documents and against the linked issue.
6. Classify each finding with exactly one severity and derive the verdict.

| The change touches | Read and apply |
|---|---|
| Anything | `AGENTS.md` (constraints, testing expectations, PR checklist) |
| PowerShell code | `STYLEGUIDE.md` |
| Workflow, request or configuration handling; auth; events; logging | `docs/about/security.md` |
| Engine behavior (planning, execution, conditions) | `docs/about/concepts.md` |
| Steps | `docs/extend/steps.md`, `docs/extend/events.md` |
| Providers | `docs/extend/providers.md`, `docs/develop/testing.md` |
| Capabilities | `docs/reference/capabilities.md` |
| Extension points | `docs/extend/extensibility.md` |
| Tests | `docs/develop/testing.md` |
| Public cmdlets, step help, `docs/reference/*` | `CONTRIBUTING.md` (generated references) |
| Completeness of the PR | `CONTRIBUTING.md` (Definition of Done) |

If two documents conflict, the more specific one wins (`AGENTS.md` section 9).

Beyond the documented rules, always check:

- **Correctness:** logic errors, wrong conditions, unhandled `$null`/empty cases, broken error handling;
  behavior matches the linked issue.
- **CI workflows** (`.github/workflows/*`): least-privilege `permissions:`, no untrusted input interpolated into
  `run:` scripts, no `pull_request_target` combined with a checkout of PR code.

Only report findings you can tie to a concrete file or line, with either a concrete failure scenario or a reference to
the violated rule (document and section). Do not report preferences that no document backs.

## Severity levels

| Severity | Meaning |
|---|---|
| `CRITICAL` | Must not be merged. Causes wrong results or data loss, or violates a trust boundary from `docs/about/security.md` or an architectural constraint from `AGENTS.md` section 4. Includes CI workflow changes that expose tokens or privileges to untrusted code. |
| `MAJOR` | Should be fixed before merge, but is not dangerous. Typically an unmet item of the Definition of Done (`CONTRIBUTING.md`, `AGENTS.md` section 8) or a `MUST` rule from a domain document that has no security or correctness impact. |
| `MINOR` | Improvement worth doing, e.g. a `STYLEGUIDE.md` rule not enforced by PSScriptAnalyzer, or a missing edge-case test. |
| `NIT` | Optional polish. |

When unsure between two severities, choose the lower one and state the uncertainty.

## Verdict

- `BLOCK` if, and only if, there is at least one `CRITICAL` finding.
- `PASS` otherwise, including when `MAJOR` findings exist.

State the verdict together with a one-sentence reason (for `BLOCK`, name the critical finding).

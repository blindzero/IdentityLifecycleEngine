---
title: Plan Export
sidebar_label: Plan Export
---

# Plan Export (User Guide)

## Why export a plan?
Plan export provides a reproducible, machine-readable representation of the planned actions IdLE intends to run.
This is useful to:

- Review and approve a plan before execution (four-eyes principle).
- Persist evidence for audit and incident investigations.
- Compare changes over time (for example, when templates or defaults change).
- Integrate IdLE planning into CI pipelines (validate workflows without executing them).

## What a plan export contains
A plan export typically includes:

- Metadata about the exported plan (name, workflow, timestamps).
- The planned step list in the order IdLE intends to execute it.
- Per-step resolved providers and parameters (as applicable).
- Capability information (if exported) to help with validation and portability.

For the exact format and normative rules, see:
- `Plan Export Specification` in `Reference -> Specs`.

## Typical workflow

1. Plan
   - Load workflow definition(s)
   - Resolve templates and inputs
   - Evaluate conditions (steps may become NotApplicable)

2. Export
   - Serialize the planned steps into a JSON export

3. Review
   - Human review (pull request, change record) or automated checks (linting)

4. Execute
   - Run IdLE against the reviewed plan export (where supported)

## Example: export for review

```powershell
# Example only. Adjust parameters to your environment.
$plan = New-IdlePlan -WorkflowPath './workflows/joiner.json' -IdentityId 'jdoe'
Export-IdlePlan -Plan $plan -Path './artifacts/joiner.plan.json'
```

### Review tips
- Verify provider selection matches your intent (especially in multi-provider environments).
- Ensure sensitive values are not embedded in exported parameters.
- Confirm step ordering and prerequisite behavior.

## Handling secrets
Do not store secrets in exported plan files.

Recommended patterns:
- Use secret providers (environment variables, vault providers, injected runtime secrets).
- Store only secret references in workflow definitions and resolve them at execution time.
- Ensure logs and event sinks redact sensitive values.

## CI usage
Plan export can be used as a build artifact:

- Generate a plan export from a known input set.
- Validate the export with schema checks (if available).
- Compare against a known-good baseline (golden file) to detect unexpected drift.

## Troubleshooting

### MDX build errors when documenting exports
If you document placeholders like `{{...}}`, `{Name}` or examples like `@{ Key = 'Value' }`,
wrap them in inline code or fenced code blocks to avoid MDX parsing issues.

## See also
- Plan Export Specification (Reference -> Specs)

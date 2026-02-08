---
title: Plan Export
sidebar_label: Plan Export
---

# Plan Export

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

For the exact format and normative rules, see [Plan Export Specification](../reference/specs/plan-export.md).

## Typical use of plan export

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
$request = New-IdleLifecycleRequest -LifecycleEvent 'Joiner' -IdentityKeys @{ EmployeeId = 'jdoe' }
$providers = @{ Identity = New-IdleMockIdentityProvider }
$plan = New-IdlePlan -WorkflowPath './workflows/joiner.psd1' -Request $request -Providers $providers
Export-IdlePlan -Plan $plan -Path './artifacts/joiner.plan.json'
```

:::note

Exported plans typically do not include provider objects. When executing an exported plan,
you must supply providers at execution time.

:::

### Review tips

- Verify provider selection matches your intent (especially in multi-provider environments).
- Ensure sensitive values are not embedded in exported parameters.
- Confirm step ordering and prerequisite behavior.

## CI usage

Plan export can be used as a build artifact:

- Generate a plan export from a known input set.
- Validate the export with schema checks (if available).
- Compare against a known-good baseline (golden file) to detect unexpected drift.

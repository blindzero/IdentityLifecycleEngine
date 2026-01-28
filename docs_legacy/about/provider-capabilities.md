---
title: Provider capabilities
---

IdLE uses **capabilities** as the contract boundary between:

- **Steps** (what is required)
- **Providers** (what is available)

This document explains the capability model, how capability validation fits into the planning flow, and how step packs and providers participate in the contract.

For the complete capability catalog (IDs, meanings, and naming rules), see: **Reference → Capabilities**.

## Motivation

IdLE is designed to run in different environments with different provider implementations.
To keep the core engine generic and portable, IdLE uses capabilities to enable:

- deterministic, fail-fast validation during planning
- clear error messages when prerequisites are missing
- provider depth without hard-coding provider-specific assumptions into the engine
- reusable contract tests for any provider module

## Terminology

### Capability

A capability is a **stable string identifier** describing a feature a provider can perform (for example: identity read, entitlement assignment, mailbox operations).

The capability identifier format and the capability catalog are intentionally documented separately to keep this document focused on the model.

### Entitlement capability set

If a provider supports entitlement assignments, IdLE treats the entitlement operations as a *set* (list, grant, revoke). This prevents partial implementations from producing ambiguous or unsafe behavior.

## High-level flow

The following describes the end-to-end flow with capability validation included.

```text
Workflow Definition (PSD1)
        |
        v
Plan Builder (New-IdlePlan / New-IdlePlanObject)
        |
        |-- loads step metadata catalog:
        |   - discovers loaded IdLE.Steps.* modules
        |   - merges their Get-IdleStepMetadataCatalog outputs
        |   - applies host supplements (Providers.StepMetadata)
        |
        |-- normalizes steps (Name/Type/With/Condition)
        |   - derives RequiresCapabilities from the metadata catalog
        |
        |-- capability validation (fail fast)
        |   - collects required capabilities from all steps
        |   - discovers available capabilities from providers
        |   - compares and throws on missing capabilities
        |
        v
Plan artifact (IdLE.Plan) is created
        |
        v
Plan execution (Invoke-IdlePlan / Invoke-IdlePlanObject)
        |
        v
Steps execute
```

Key point: **planning is the primary enforcement point**.
If a plan cannot be executed due to missing provider functionality, the plan build fails early and deterministically.

## Provider advertisement

Providers advertise capabilities explicitly via a method named `GetCapabilities()`.

The method returns a string list, for example:

```powershell
$provider | Add-Member -MemberType ScriptMethod -Name GetCapabilities -Value {
    return @(
        'IdLE.Identity.Read'
        'IdLE.Identity.Attribute.Ensure'
        'IdLE.Identity.Disable'
    )
} -Force
```

### Contract requirements

Every provider intended for use with IdLE should expose `GetCapabilities()` and return:

- only valid capability identifiers
- no duplicates
- a deterministic set (order-insensitive)

IdLE includes a reusable Pester contract to enforce this.

## Step requirements

Steps declare required capabilities via **step metadata catalogs** owned by step packs.

### Step pack ownership

Step packs (`IdLE.Steps.*` modules) own metadata for their step types via the `Get-IdleStepMetadataCatalog` function.

Each step pack exports a case-insensitive hashtable mapping:

- **Key**: StepType (string, for example: `IdLE.Step.DisableIdentity`)
- **Value**: metadata hashtable containing at least:
  - `RequiredCapabilities`: string or string array (normalized to a string array by Core)

Example from `IdLE.Steps.Common`:

```powershell
function Get-IdleStepMetadataCatalog {
    $catalog = [hashtable]::new([System.StringComparer]::OrdinalIgnoreCase)

    $catalog['IdLE.Step.DisableIdentity'] = @{
        RequiredCapabilities = @('IdLE.Identity.Disable')
    }

    $catalog['IdLE.Step.EnsureAttribute'] = @{
        RequiredCapabilities = @('IdLE.Identity.Attribute.Ensure')
    }

    return $catalog
}
```

### Discovery and merge

During plan building, IdLE.Core:

1. Discovers all loaded modules matching `IdLE.Steps.*` that export `Get-IdleStepMetadataCatalog`
2. Calls each function and merges the returned catalogs deterministically (by module name ascending)
3. Fails fast with `DuplicateStepTypeMetadata` if the same step type appears in multiple step packs

### Host supplements (custom step types only)

Hosts may provide metadata for **new, host-defined** step types via `Providers.StepMetadata`:

```powershell
$providers = @{
    StepMetadata = @{
        'Custom.Step.SpecialAction' = @{
            RequiredCapabilities = @('Custom.Capability.SpecialAction')
        }
    }
}
```

Important: Host metadata is **supplement-only**. Hosts cannot override step pack metadata. Attempting to provide metadata for a step type already owned by a loaded step pack will result in `DuplicateStepTypeMetadata`.

## Capability validation

Capability validation is performed during plan build:

1. Load step metadata catalog (from step packs and host supplements)
2. Normalize steps and derive `RequiresCapabilities` from metadata
3. Collect required capabilities from all steps (including OnFailureSteps)
4. Discover available capabilities from all provider instances passed via `-Providers`
5. Compare required vs. available
6. Throw a deterministic error if any required capabilities are missing

The thrown error message is designed for good UX and for automated diagnostics in CI logs, and typically includes:

- MissingCapabilities
- AffectedSteps
- AvailableCapabilities

### Error: MissingStepTypeMetadata

If a workflow references a step type that has no metadata entry, plan building fails with `MissingStepTypeMetadata`.

Remediation:

1. Import/load the step pack module (`IdLE.Steps.*`) that owns the step type, or
2. For custom/host-defined step types only, provide `Providers.StepMetadata`

### Error: DuplicateStepTypeMetadata

If the same step type appears in multiple step packs, or if a host attempts to override step pack metadata, plan building fails with `DuplicateStepTypeMetadata`.

This ensures clear ownership and prevents ambiguous behavior.

## Provider discovery from `-Providers`

The engine treats the `-Providers` argument as a host-controlled bag of objects.

For capability discovery, IdLE currently extracts candidate providers from:

- hashtable values (excluding known non-provider keys like `StepRegistry`)
- public properties on PSCustomObject provider bags (also excluding StepRegistry)

This keeps the engine host-agnostic while still allowing deterministic capability validation.

## Migration and inference

During migration, IdLE may infer a minimal capability set for legacy providers that do not yet implement `GetCapabilities()`.

This inference is intentionally conservative to avoid overstating what a provider can do.

Once all providers in the ecosystem advertise capabilities explicitly, inference can be disabled to make the contract stricter.

## Testing

### Provider contract tests

Providers should include contract tests that validate capability advertisement.

### Planning tests

Planning tests should cover:

- fail-fast behavior when capabilities are missing
- successful plan build when capabilities are available

## Future extensions

Potential follow-ups (not required for the initial capability model):

- runtime defensive checks (optional) during step execution
- richer capability metadata (versioning, parameters) if ever needed
- mapping capabilities to provider identities (which provider satisfied what), if multi-provider routing becomes necessary

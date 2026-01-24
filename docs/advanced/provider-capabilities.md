# Provider capabilities

This document describes IdLE's capability-based provider model and how capability validation fits into the planning and execution flow.

## Motivation

IdLE is designed to run in different environments with different provider implementations.
To keep the core engine generic and portable, IdLE uses **capabilities** as the contract boundary between:

- **Steps** (what is required)
- **Providers** (what is available)

Capabilities enable:

- deterministic, fail-fast validation during planning
- clear error messages when prerequisites are missing
- provider depth without hard-coding provider-specific assumptions into the engine
- re-usable contract tests for any provider module

## Terminology

### Capability

A capability is a **stable string identifier** describing a feature a provider can perform.

Naming convention:

- dot-separated segments
- no whitespace
- starts with a letter
- examples: `IdLE.Identity.Read`, `IdLE.Identity.Disable`, `IdLE.Entitlement.List`

### Entitlement capability set

Providers that support entitlement assignments should advertise the minimal trio:

- `IdLE.Entitlement.List` — list entitlements assigned to a specific identity
- `IdLE.Entitlement.Grant` — assign an entitlement to an identity
- `IdLE.Entitlement.Revoke` — remove an entitlement from an identity

## High-level flow

The following describes the end-to-end flow with capability validation included.

```text
Workflow Definition (PSD1)
        |
        v
Plan Builder (New-IdlePlan / New-IdlePlanObject)
        |
        |-- loads step metadata catalog:
        |      - discovers loaded IdLE.Steps.* modules
        |      - merges their Get-IdleStepMetadataCatalog outputs
        |      - applies host supplements (Providers.StepMetadata)
        |
        |-- normalizes steps (Name/Type/With/Condition)
        |      - derives RequiresCapabilities from metadata catalog
        |
        |-- capability validation (fail fast)
        |      - collects required capabilities from all steps
        |      - discovers available capabilities from providers
        |      - compares and throws on missing capabilities
        |
        v
Plan artifact (IdLE.Plan) is created
        |
        v
Plan execution (Invoke-IdlePlan / Invoke-IdlePlanObject)
        |
        v
Steps execute (optional runtime defensive checks may be added later)
```

Key point: **planning is the primary enforcement point**.
If a plan cannot be executed due to missing provider functionality, the plan build fails early and deterministically.

## Provider advertisement

Providers advertise capabilities explicitly via a method named:

- `GetCapabilities()`

The method returns a string list, e.g.:

```powershell
$provider | Add-Member -MemberType ScriptMethod -Name GetCapabilities -Value {
    return @(
        'IdLE.Identity.Read'
        'IdLE.Identity.Attribute.Ensure'
        'IdLE.Identity.Disable'
    )
} -Force
```

### Contract requirement

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
- **Key**: `StepType` (string, e.g., `IdLE.Step.DisableIdentity`)
- **Value**: metadata hashtable containing at least:
  - `RequiredCapabilities`: string or string[] (normalized to string[] by Core)

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

During plan building, `IdLE.Core`:

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

**Important**: Host metadata is **supplement-only**. Hosts cannot override step pack metadata. Attempting to provide metadata for a step type already owned by a loaded step pack will result in `DuplicateStepTypeMetadata`.

Workflow definitions must **not** declare `RequiredCapabilities` or `RequiresCapabilities` on individual steps. Capabilities are derived from step metadata catalogs during plan building.

Example workflow step:
```powershell
@{
  Name = 'Disable identity'
  Type = 'IdLE.Step.DisableIdentity'
  With = @{
    IdentityKey = '{{ Request.Username }}'
    Provider    = 'Identity'
  }
}
```

## Capability validation

Capability validation is performed during plan build:

1. Load step metadata catalog (from step packs and host supplements)
2. Normalize steps and derive `RequiresCapabilities` from metadata
3. Collect required capabilities from all steps (including `OnFailureSteps`)
4. Discover available capabilities from all provider instances passed via `-Providers`
5. Compare required vs. available
6. Throw a deterministic error if any required capabilities are missing

The thrown error message includes:

- `MissingCapabilities: ...`
- `AffectedSteps: ...`
- `AvailableCapabilities: ...`

This is designed for good UX and for automated diagnostics in CI logs.

### Error: MissingStepTypeMetadata

If a workflow references a step type that has no metadata entry, plan building fails with `MissingStepTypeMetadata`.

Remediation:
1. Import/load the step pack module (`IdLE.Steps.*`) that owns the step type, OR
2. For custom/host-defined step types only, provide `Providers.StepMetadata`

### Error: DuplicateStepTypeMetadata

If the same step type appears in multiple step packs, or if a host attempts to override step pack metadata, plan building fails with `DuplicateStepTypeMetadata`.

This ensures clear ownership and prevents ambiguous behavior.

## Provider discovery from `-Providers`

The engine treats the `-Providers` argument as a host-controlled "bag of objects".
For capability discovery, IdLE currently extracts candidate providers from:

- hashtable values (excluding known non-provider keys like `StepRegistry`)
- public properties on PSCustomObject provider bags (also excluding `StepRegistry`)

This keeps the engine host-agnostic while still allowing deterministic capability validation.

## Migration and inference

During migration, IdLE may infer a minimal capability set for legacy providers that do not yet implement `GetCapabilities()`.

This inference is intentionally conservative to avoid overstating what a provider can do.

Once all providers in the ecosystem advertise capabilities explicitly, inference can be disabled to make the contract stricter.

## Testing

### Provider contract tests

Providers should include contract tests that validate capability advertisement:

- `tests/ProviderContracts/ProviderCapabilities.Contract.ps1`

A provider test binds the contract to a provider instance via a factory function.

### Planning tests

Planning tests should cover:

- fail-fast behavior when capabilities are missing
- successful plan build when capabilities are available

## Future extensions

Potential follow-ups (not required for the initial capability model):

- runtime defensive checks (optional) during step execution
- richer capability metadata (versioning, parameters) if ever needed
- mapping capabilities to provider identities (which provider satisfied what), if multi-provider routing becomes necessary

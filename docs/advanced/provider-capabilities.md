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
        |-- normalizes steps (Name/Type/With/Condition/RequiresCapabilities)
        |
        |-- NEW: capability validation (fail fast)
        |      - collect required capabilities from steps
        |      - discover available capabilities from providers
        |      - compare and throw on missing capabilities
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

Steps can declare required capabilities in workflow definitions using the optional key:

- `RequiresCapabilities`

Supported shapes:

- missing / `$null` -> no requirements
- string -> single capability
- string array -> multiple capabilities

Example:

```powershell
@{
  Name                 = 'Disable identity'
  Type                 = 'DisableIdentity'
  RequiresCapabilities = @('IdLE.Identity.Read', 'IdLE.Identity.Disable')
}
```

During planning, IdLE normalizes this into a stable, sorted, unique string array on each plan step.

## Capability validation

Capability validation is performed during plan build:

1. Collect required capabilities from all steps (`RequiresCapabilities`)
2. Discover available capabilities from all provider instances passed via `-Providers`
3. Compare required vs. available
4. Throw a deterministic error if any required capabilities are missing

The thrown error message includes:

- `MissingCapabilities: ...`
- `AffectedSteps: ...`
- `AvailableCapabilities: ...`

This is designed for good UX and for automated diagnostics in CI logs.

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

---
title: "Design: Step contract (engine-owned validation and provider resolution)"
sidebar_label: "Design: Step contract"
---

# Design: Step contract

| | |
| --- | --- |
| **Status** | Implemented (see [Implementation notes](#implementation-notes)) |
| **Issue** | [#324](https://github.com/blindzero/IdentityLifecycleEngine/issues/324) |
| **Target** | v1.0.0 |
| **Affects** | Step handlers, step metadata catalogs, `Providers.StepMetadata` / `Providers.StepRegistry` (host-defined steps) |
| **Unchanged** | Host API (`New-IdlePlan`, `Invoke-IdlePlan`, `Providers`), provider contract, workflow `With` values |

## Problem

Every step handler repeats work that the engine already knows how to do:

- `With` is a hashtable, required keys exist (already validated at plan time via `WithSchema`).
- `Context.Providers` exists, the provider alias is resolved (`With.Provider` or a hard-coded default) and supplied.
- Auth sessions are acquired (`Invoke-IdleProviderMethod`).
- `IdLE.StepResult` is constructed by hand.

In `Invoke-IdleStepDisableIdentity` this is ~35 of ~50 lines. `Provider`, `AuthSessionName` and
`AuthSessionOptions` are repeated in all 16 catalog entries. `WithSchema` lists only key names, so type errors
(e.g. `State = 'present '`, `Entitlement = 'CN=...'`) surface at execution time inside handlers or providers.

## Principle

The engine owns validation, provider resolution, authentication and the result shape.
A step handler contains only its domain logic.

## 1. Catalog entry

```powershell
'IdLE.Step.EnsureEntitlement' = @{
    Handler              = 'Invoke-IdleStepEnsureEntitlement'
    RequiredCapabilities = @('IdLE.Entitlement.List', 'IdLE.Entitlement.Grant', 'IdLE.Entitlement.Revoke')

    # Optional. Present = the step uses exactly one provider; the engine resolves it.
    Provider             = @{ DefaultAlias = 'Identity' }

    WithSchema           = @{
        Keys = @{
            IdentityKey = @{ Type = 'String'; Required = $true }
            Entitlement = @{
                Type = 'Hashtable'; Required = $true
                Keys = @{
                    Kind        = @{ Type = 'String'; Required = $true }
                    Id          = @{ Type = 'String'; Required = $true }
                    DisplayName = @{ Type = 'String' }
                }
            }
            State       = @{ Type = 'String'; AllowedValues = @('Present', 'Absent'); Default = 'Present' }
        }
    }
}
```

### Provider declaration

- `Provider = @{ DefaultAlias = '<alias>' }` declares that the step uses one provider.
  The engine then adds the **common keys** to the step's schema; they must not be declared in `Keys`:

  | Key | Type | Meaning |
  | --- | --- | --- |
  | `Provider` | String | Provider alias; defaults to `DefaultAlias`. |
  | `AuthSessionName` | String | Auth session routing key passed to the broker. |
  | `AuthSessionOptions` | Hashtable | Data-only broker options (ScriptBlocks rejected). |

- `AuthSessionNameFromAlias = $true` (optional) names the auth session after the resolved alias when
  `With.AuthSessionName` is not set (mailbox steps).
- No `Provider` entry: the step uses no provider (e.g. `IdLE.Step.EmitEvent`); the common keys are not accepted.
- All current steps use at most one provider alias. Multiple providers per step are out of scope; if needed later,
  `Provider` can become a map of named roles without breaking the single-provider form.

### WithSchema

`WithSchema.Keys` maps each key to a key schema. `RequiredKeys` / `OptionalKeys` are removed.

| Property | Applies to | Meaning |
| --- | --- | --- |
| `Type` | all (required) | `String`, `Int`, `Bool`, `Hashtable`, `Array`, `Any` |
| `Required` | all | `$true` = must be present and non-null. Default `$false`. |
| `Default` | all | Value used when the key is absent. Must match `Type`. Not allowed with `Required`. |
| `AllowedValues` | `String`, `Int` | Value must be one of the list (strings compared case-insensitively, result normalized to the listed casing). |
| `AllowEmpty` | `String`, `Array` | `$true` = empty string / empty array allowed. Default `$false`. |
| `Keys` | `Hashtable` | Nested key schemas (same format, recursive). Unknown nested keys fail. |
| `AllowAdditionalKeys` | `Hashtable` (and `WithSchema` root) | `$true` = keys not listed in `Keys` are accepted unchecked. |
| `Items` | `Array` | Key schema applied to every element (e.g. `@{ Type = 'Hashtable'; Keys = @{ ... } }`). |

Rules:

- A `Hashtable` without `Keys` accepts any content (e.g. `EnsureAttributes.Attributes`).
- No implicit type coercion: `'600'` is not an `Int`, `'true'` is not a `Bool`. PSD1 literals and pure template
  placeholders (`'{{Request.Intent.TimeoutSeconds}}'`) already keep their type, so plan-time checking is exact.
- `Int` accepts `[int]` and `[long]`; `Array` accepts any non-string `IEnumerable` except dictionaries.
- Optional keys set to `$null` are treated as absent (defaults apply). `$null` values inside a `Hashtable` without
  `Keys` (e.g. "clear attribute" values in `Attributes`) are passed through.
- The schema itself is data-only and validated when the catalog is loaded (`InvalidWithSchema`).

### Validation time

All `With` checks run at **plan time** after template resolution, with the full path in the error
(`With.Entitlement.Kind`). Defaults are applied at plan time, so the plan (and plan export) shows the effective `With`.

## 2. Handler signature

```powershell
function Invoke-IdleStepDisableIdentity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [hashtable] $With,
        [Parameter(Mandatory)] [object] $Provider
    )

    $result = $Provider.Invoke('DisableIdentity', @($With.IdentityKey))
    return @{ Changed = [bool]$result.Changed }
}
```

| Parameter | Passed | Content |
| --- | --- | --- |
| `With` | always (required) | Validated `With` **without** the common keys, defaults applied. |
| `Provider` | only if the catalog declares `Provider` | Provider handle (see below). |
| `Context` | if declared | Execution context (`EventSink`, `Request`, `Plan`, `CorrelationId`, `Actor`). |
| `Step` | if declared | Read-only step metadata (`Name`, `Type`). |

- The engine checks the handler's parameters before the first attempt:
  `With` is mandatory; `Provider` must be declared if and only if the catalog declares `Provider`.
- Handlers written against the old contract (no `With` parameter) fail with `LegacyStepHandler`.

### Provider handle

The engine resolves the alias (`With.Provider` or `DefaultAlias`), looks it up in `Providers` and passes a handle
(`PSTypeName = 'IdLE.ProviderHandle'`):

| Member | Meaning |
| --- | --- |
| `Alias` | Resolved provider alias. |
| `Invoke(MethodName, Arguments)` | Calls the provider method. `Arguments` exclude `AuthSession`; the session is inserted at the position the method declares it (e.g. `ListEntitlements(IdentityKey, AuthSession, Kind)`). |
| `HasMethod(MethodName)` | `$true` if the provider implements the method (optional capabilities such as bulk operations). |
| `HasParameter(MethodName, ParameterName)` | `$true` if the method declares the parameter (e.g. `Kind` on `ListEntitlements`). |

- Auth session behavior is unchanged from today's `Invoke-IdleProviderMethod`: acquired on the first `Invoke` that
  needs it (method declares `AuthSession`, or `AuthSessionName` is set), then cached for the step attempt.
- The handle does not expose the raw provider object. Steps cannot bypass the auth logic.
- Providers that expose an `EventSink` property receive the run's event sink (previously done by the mailbox
  permissions step itself).
- The same resolved alias feeds `Request.Context.Current` for preconditions (today `Current` ignores the step's
  default alias when `With.Provider` is not set).

## 3. Handler result

A handler returns `$null` or a hashtable:

| Key | Type | Meaning |
| --- | --- | --- |
| `Changed` | Bool | The step changed external state. Default `$false`. |
| `Data` | Hashtable | Structured step output (e.g. per-attribute results, skipped entitlements). |
| `State` | Hashtable | Values for downstream steps (reserved; see Open questions). |

- The engine builds `IdLE.StepResult` (`Name`, `Type`, `Status`, `Changed`, `Data`, `Error`, `Attempts`, `Source`).
- **Failure is always an exception.** Returning a status is not supported. Transient failures keep using the
  existing transient marker for retries.
- Unknown result keys or a non-hashtable result fail the step (`InvalidStepHandlerResult`).
- Step-specific result properties move under `Data`: `PruneEntitlements.Skipped` -> `Data.Skipped`,
  `EnsureAttributes.Attributes` -> `Data.Attributes` (already partly there).

## 4. Error codes

| Code | When | Raised at |
| --- | --- | --- |
| `LegacyWithSchema` | Catalog uses `RequiredKeys` / `OptionalKeys`. | Catalog load |
| `InvalidWithSchema` | Unknown `Type`, `Default` not matching `Type`, `Keys` on a non-hashtable, common key declared in `Keys`, ... | Catalog load |
| `LegacyStepHandler` | Handler has no `With` parameter. | Before the first attempt |
| `InvalidStepHandlerSignature` | `Provider` declared without catalog `Provider` (or vice versa). | Before the first attempt |
| `WithKeyMissing` | Required key absent or null. | Plan |
| `WithKeyUnknown` | Key not in schema (and no `AllowAdditionalKeys`). | Plan |
| `WithKeyTypeMismatch` | Value does not match `Type`. | Plan |
| `WithValueNotAllowed` | Value not in `AllowedValues`, or empty without `AllowEmpty`. | Plan |
| `ProviderNotSupplied` | Resolved alias not in `Providers`. | Execution (hosts may pass providers only to `Invoke-IdlePlan`) |
| `ProviderMethodNotImplemented` | `Invoke` of a method the provider does not implement. | Execution |
| `InvalidStepHandlerResult` | Result is not `$null` / hashtable, or contains unknown keys. | Execution |

Messages start with the code, followed by step name, step type and the path (e.g. `With.Entitlement.Kind`),
matching the existing `ReservedNamespace` style.

## 5. Migration example

### Catalog

```powershell
# Before
'IdLE.Step.DisableIdentity' = @{
    Handler              = 'Invoke-IdleStepDisableIdentity'
    RequiredCapabilities = @('IdLE.Identity.Disable')
    WithSchema           = @{
        RequiredKeys = @('IdentityKey')
        OptionalKeys = @('Provider', 'AuthSessionName', 'AuthSessionOptions')
    }
}

# After
'IdLE.Step.DisableIdentity' = @{
    Handler              = 'Invoke-IdleStepDisableIdentity'
    RequiredCapabilities = @('IdLE.Identity.Disable')
    Provider             = @{ DefaultAlias = 'Identity' }
    WithSchema           = @{
        Keys = @{ IdentityKey = @{ Type = 'String'; Required = $true } }
    }
}
```

### Handler

```powershell
# Before (~50 lines): checks With, Context.Providers, alias, calls Invoke-IdleProviderMethod, builds IdLE.StepResult
function Invoke-IdleStepDisableIdentity {
    param([object] $Context, [object] $Step)

    $with = $Step.With
    if ($null -eq $with -or -not ($with -is [hashtable])) { throw "DisableIdentity requires 'With' to be a hashtable." }
    if (-not $with.ContainsKey('IdentityKey')) { throw "DisableIdentity requires With.IdentityKey." }
    $providerAlias = if ($with.ContainsKey('Provider')) { [string]$with.Provider } else { 'Identity' }
    # ... Context.Providers checks ...
    $result = Invoke-IdleProviderMethod -Context $Context -With $with -ProviderAlias $providerAlias `
        -MethodName 'DisableIdentity' -MethodArguments @([string]$with.IdentityKey)
    # ... Changed extraction, [pscustomobject]@{ PSTypeName = 'IdLE.StepResult'; ... } ...
}

# After
function Invoke-IdleStepDisableIdentity {
    param(
        [Parameter(Mandatory)] [object] $Context,
        [Parameter(Mandatory)] [hashtable] $With,
        [Parameter(Mandatory)] [object] $Provider
    )

    $result = $Provider.Invoke('DisableIdentity', @($With.IdentityKey))
    return @{ Changed = [bool]$result.Changed }
}
```

### Host-defined steps

Host steps (`Providers.StepMetadata` + `Providers.StepRegistry`) use the same catalog entry format and handler
signature. Workflows are unchanged unless they contain values that were silently accepted before but violate the
new types (these now fail at plan time).

## 6. Breaking changes

- Catalog format: `RequiredKeys` / `OptionalKeys` replaced by `Keys` (+ `Provider`). No compatibility layer.
- Handler signature: `-With` / `-Provider`, hashtable result, failure only via exception. No compatibility layer.
- `IdLE.StepResult`: step-specific properties move under `Data` (`Skipped`, `Attributes`).
- Workflows with wrongly typed `With` values now fail at plan time instead of execution time.
- `Invoke-IdleProviderMethod` is removed (replaced by the provider handle); `Test-IdleProviderMethodParameter`
  becomes private.

All first-party catalogs and handlers move in one change; the changelog/release notes carry the migration example.

## 7. Implementation plan

1. **Core** (one PR, atomic because there is no compatibility layer): schema validator, catalog loader
   (`LegacyWithSchema`, `InvalidWithSchema`), handler signature check, provider handle, result normalization,
   `Current` via resolved alias; migrate all 16 first-party catalogs and handlers and their tests.
2. **Docs and tooling**: `docs/extend/steps.md` (contract), step reference generator renders the typed `With` table
   from the schema (types, required, defaults, allowed values) instead of "see step description".
3. **#289** (entitlement `Kind` per entry) builds on the nested schema (`Entitlements.Items.Keys.Kind`).

## Implementation notes

Differences from the proposal and findings during implementation:

- `-Context` is optional (passed when declared), so handlers without context needs carry no unused parameter.
- `ProviderNotSupplied` is checked at execution only; plans are often built with a subset of providers.
- `Provider.AuthSessionNameFromAlias` keeps the mailbox steps' convention (session named after the alias).
- The engine wires `Context.EventSink` into providers exposing an `EventSink` property.
- Provider exceptions keep a single level of `MethodInvocationException` wrapping, as with direct calls.
- `Context.AcquireAuthSession` now accepts an empty name, which requests the broker's default session. Before, the
  default-session path failed for every provider method declaring `AuthSession` when `With.AuthSessionName` was
  not set.
- `Copy-IdleDataObject` and template resolution returned single-element arrays as scalars and empty arrays as
  `$null` (PowerShell pipeline unrolling); both now keep arrays.
- `IdLE.Step.EmitEvent` no longer accepts `Provider` / `AuthSessionName` / `AuthSessionOptions`.
- `IdLE.Step.PruneEntitlementsEnsureKeep` shares a private implementation with `IdLE.Step.PruneEntitlements`
  instead of injecting an undeclared `EnsureKeepEntitlements` key.
- Workflow examples used `@{ ValueFrom = '...' }`, which the engine never supported; they now use templates.
- Open: `State` propagation to later steps (the result key is reserved and returned as-is), tracked in #346.

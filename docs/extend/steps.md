# Steps and Metadata

## Purpose

Steps are the fundamental building blocks of execution in IdLE.
They encapsulate domain logic and perform concrete actions during the execution
of a lifecycle plan.

This document defines the conceptual model of a step, the meaning of step metadata,
and the expectations placed on step implementations. It serves as a normative
reference for step authors and reviewers.

---

## Concept

### What is a step?

A step is a **self-contained unit of work** executed as part of a plan.

A step:

- performs a single, well-defined responsibility
- operates on the execution context provided by the engine
- may interact with external systems through providers
- reports its outcome through status and events

Steps do not orchestrate other steps and do not control execution flow beyond
their own outcome.

### Design goals

Steps should be:

- idempotent (converge towards the desired state)
- deterministic (same inputs produce the same plan)
- provider-agnostic (use provider contracts, not direct system calls)
- safe for preview (planning must not change external state)

### Step lifecycle

During execution, each step follows a consistent lifecycle:

1. The engine signals the start of the step
2. The step evaluates its own applicability (if applicable)
3. The step performs its domain logic
4. The step reports its result and any relevant events

The engine is responsible for invoking steps and sequencing their execution.

### Step metadata

Metadata describes **what a step is**, not **how it is implemented**.

Typical conceptual metadata includes:

- **Name**
  - Human-readable identifier
- **Purpose**
  - Description of what the step is intended to achieve
- **Idempotency**
  - Whether repeated execution leads to the same state
- **Inputs**
  - Expected configuration values or request data
- **Outputs**
  - State changes or information produced
- **Side effects**
  - External systems affected by the step

### Step metadata contract

Every step type registered with the engine **must** declare a data-only metadata entry:

```powershell
'IdLE.Step.EnsureEntitlement' = @{
    Handler              = 'Invoke-IdleStepEnsureEntitlement'   # step packs only
    RequiredCapabilities = @('IdLE.Entitlement.List', 'IdLE.Entitlement.Grant', 'IdLE.Entitlement.Revoke')
    Provider             = @{ DefaultAlias = 'Identity' }       # optional: the step uses one provider
    WithSchema           = @{
        Keys = @{
            IdentityKey = @{ Type = 'String'; Required = $true }
            Entitlement = @{
                Type     = 'Hashtable'
                Required = $true
                Keys     = @{
                    Kind = @{ Type = 'String'; Required = $true }
                    Id   = @{ Type = 'String'; Required = $true }
                }
            }
            State       = @{ Type = 'String'; AllowedValues = @('Present', 'Absent'); Default = 'Present' }
        }
    }
}
```

**`Provider`** (optional): `@{ DefaultAlias = '<alias>' }` declares that the step uses exactly one provider.
The engine then accepts these `With` keys for the step (they must not be declared in `Keys`):

| Key | Type | Meaning |
| --- | --- | --- |
| `Provider` | String | Provider alias in `Providers`; defaults to `DefaultAlias`. |
| `AuthSessionName` | String | Auth session routing key passed to the `AuthSessionBroker`. |
| `AuthSessionOptions` | Hashtable | Data-only broker options. |

`AuthSessionNameFromAlias = $true` names the auth session after the provider alias when `With.AuthSessionName` is
not set (used by the mailbox steps: `ExchangeOnline`). Steps without `Provider` reject the three keys.

**`WithSchema`** (mandatory): `Keys` maps each `With` key to a key schema:

| Property | Applies to | Meaning |
| --- | --- | --- |
| `Type` | all (required) | `String`, `Int`, `Bool`, `Hashtable`, `Array`, `Any` |
| `Required` | all | Key must be present and not `$null`. |
| `Default` | all | Applied when the key is absent; must match `Type`; not combined with `Required`. |
| `AllowedValues` | `String`, `Int` | Strings match case-insensitively and are normalized to the listed casing. |
| `AllowEmpty` | `String`, `Array` | Allow `''` / `@()` (default: not allowed). |
| `Keys` | `Hashtable` | Nested key schemas; unknown nested keys fail. Without `Keys`, any content is accepted. |
| `AllowAdditionalKeys` | `Hashtable`, `WithSchema` | Accept keys not listed in `Keys`. |
| `Items` | `Array` | Key schema for every element. |

**Rules:**

- `With` is validated at plan time, after template resolution. Defaults are applied, so the plan (and the plan
  export) contains the effective `With`, including the resolved `Provider`.
- No implicit type conversion: `'600'` is not an `Int`. Pure template placeholders keep the type of the request value.
- Optional keys set to `$null` are treated as absent.
- Errors name the step, the step type and the full path, e.g.
  `WithKeyMissing: Step 'Grant' (type 'IdLE.Step.EnsureEntitlement'): With.Entitlement.Kind is required.`
  Codes: `WithKeyMissing`, `WithKeyUnknown`, `WithKeyTypeMismatch`, `WithValueNotAllowed`.
- Invalid metadata fails when the catalog is loaded: `LegacyWithSchema` (old `RequiredKeys`/`OptionalKeys` format),
  `InvalidWithSchema` (any other shape error).
- Metadata must be data-only — ScriptBlocks are rejected.

Host-supplied step types may supplement (but not override) the catalog via `Providers.StepMetadata`.

### Step handler contract

The engine validates inputs, resolves the provider, handles authentication and builds the step result.
A handler contains only the step's domain logic:

```powershell
function Invoke-ContosoStepSyncManager {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [hashtable] $With,
        [Parameter(Mandatory)] [object] $Provider
    )

    $result = $Provider.Invoke('SyncManager', @($With.IdentityKey))
    return @{ Changed = [bool]$result.Changed }
}
```

| Parameter | Passed | Content |
| --- | --- | --- |
| `With` | always (required) | Validated `With` without `Provider`, `AuthSessionName`, `AuthSessionOptions`. |
| `Provider` | if and only if the metadata declares `Provider` | Provider handle (see below). |
| `Context` | if declared | Execution context (`EventSink`, `Plan`, `Request`, `CorrelationId`, `Actor`). |
| `Step` | if declared | Step metadata (`Name`, `Type`), e.g. for events. |

**Provider handle** (`IdLE.ProviderHandle`):

- `Invoke(MethodName, Arguments)` calls a provider method. `Arguments` are the method's parameters **without**
  `AuthSession`; the engine acquires the session (once per step attempt) and inserts it at the position the method
  declares (`ListEntitlements(IdentityKey, AuthSession, Kind)` is called as `Invoke('ListEntitlements', @($id, $kind))`).
- `HasMethod(MethodName)` / `HasParameter(MethodName, ParameterName)` check optional provider features.
- `Alias` is the resolved provider alias. The raw provider object is not exposed.
- Providers that expose an `EventSink` property receive the run's event sink.

**Result:** return `$null` or a hashtable with the optional keys `Changed` (Bool), `Data` (Hashtable) and `State`
(Hashtable). The engine builds `IdLE.StepResult` (`Name`, `Type`, `Status`, `Changed`, `Data`, `State`, `Error`,
`Attempts`, `Source`). Failures are reported by throwing; transient failures use the transient marker for retries.

**Errors:** `LegacyStepHandler` (no `-With` parameter, pre-1.0 contract), `InvalidStepHandlerSignature`
(`-Provider` does not match the metadata), `InvalidStepHandlerResult` (other return values, including output leaked
to the pipeline), `ProviderNotSupplied`, `ProviderMethodNotImplemented`.

### Step packs

A step pack is a module that ships a `StepMetadataCatalog.psd1` data file and declares it in its
module manifest. The engine discovers every loaded module carrying this marker:

```powershell
# Contoso.IdLE.Steps.Hr.psd1
@{
    # ...
    FunctionsToExport = @('Invoke-ContosoStepSyncManager')
    PrivateData       = @{
        IdLE = @{
            Kind        = 'StepPack'
            StepCatalog = 'StepMetadataCatalog.psd1'   # relative to the module folder
        }
    }
}
```

Each catalog entry declares its handler with the `Handler` key. The engine registers it automatically,
so hosts do not need `Providers.StepRegistry` for step pack steps:

```powershell
# Contoso.IdLE.Steps.Hr/StepMetadataCatalog.psd1
@{
    'Contoso.IdLE.Step.Hr.SyncManager' = @{
        Handler              = 'Invoke-ContosoStepSyncManager'
        RequiredCapabilities = @('Contoso.IdLE.Hr.Manager.Read')
        Provider             = @{ DefaultAlias = 'Hr' }
        WithSchema           = @{
            Keys = @{ IdentityKey = @{ Type = 'String'; Required = $true } }
        }
    }
}
```

**Rules:**

- `Handler` is a function name (string) exported by the step pack module. It is bound to the declaring
  module (`Contoso.IdLE.Steps.Hr\Invoke-ContosoStepSyncManager`); a handler from another module is rejected.
- The module does not need to be imported globally; nested modules work.
- `StepCatalog` must point to a file inside the module folder.
- A step type may be defined by only one step pack.
- Discovery uses the manifest marker only. Module names are never used for discovery or ownership.
- `Providers.StepMetadata` must not declare `Handler`; host-defined steps register their handler via
  `Providers.StepRegistry`.
- Host extension points only supplement step packs: `Providers.StepMetadata` and `Providers.StepRegistry`
  cannot redefine or replace a step type defined by a step pack (`DuplicateStepTypeMetadata`,
  `DuplicateStepHandler`).

### Step type names

Step type identifiers follow the namespace rules (owner first, then product):

| Defined by | Format | Example |
| --- | --- | --- |
| IdLE (first-party step packs in the `IdLE` bundle) | `IdLE.Step.<Area>.<Name>` | `IdLE.Step.Mailbox.GetInfo` |
| Extensions (third-party step packs, host steps) | `<Owner>.IdLE.Step.<Area>.<Name>` | `Contoso.IdLE.Step.Hr.SyncManager` |

- `IdLE.*` is reserved. Only modules shipped in the loaded `IdLE` bundle (and loaded from its folders) may
  define `IdLE.*` step types; anywhere else they are rejected with `ReservedNamespace`.
- First-party step types that do not match `IdLE.Step.<Name>` or `IdLE.Step.<Area>.<Name>` are rejected with `InvalidFirstPartyStepType`.
- Extension step types that do not match `<Owner>.IdLE.Step.<...>` are rejected with `InvalidExtensionNamespace`.
- The rules apply to step pack catalogs, `Providers.StepMetadata` and `Providers.StepRegistry`.
- Name extension modules `<Owner>.IdLE.<Area>` (e.g. `Contoso.IdLE.Hr`); `IdLE.*` module names are reserved for the
  IdLE project.

Capability identifiers follow the same scheme; see [Capabilities](../reference/capabilities.md#naming-rules).

### Provenance

Plans and execution results record which module provided each step handler and each provider
(e.g. for audits: "which code disabled this account?"):

```powershell
$plan.Steps[0].Source           # @{ Module = 'IdLE.Steps.Common'; Version = '1.0.0' }
$plan.ProviderSources['Identity']
$result.Steps[0].Source         # handler that actually ran
$result.ProviderSources['Identity']
```

- Handlers without a module (e.g. host functions registered via `Providers.StepRegistry`) and handlers that
  are not resolvable at planning time are recorded with `Module = $null` and `Version = $null`.
- `Source` records names and versions as loaded; it is not an integrity check of the module files.
- In execution results, `Source` is `$null` for steps whose handler did not run (`NotApplicable`,
  `Blocked`, `PreconditionSkipped`).
- `ProviderSources` lists only provider objects (entries exposing `GetCapabilities()`). The module of a
  provider is the module that defines its `GetCapabilities` method.
- The plan export contains the same information (`steps[].source`, `plan.providers`); see the
  [plan export specification](../reference/specs/plan-export.md).

Metadata exists to make steps:

- understandable
- reviewable
- documentable

### Idempotency expectations

Steps should be designed to be **idempotent whenever possible**.

Idempotent steps:

- can be executed multiple times without unintended side effects
- are safer in retries and error recovery scenarios
- improve predictability of plans

If a step is not idempotent, this must be clearly documented in its metadata.

### Side effects and responsibility

Steps are the only components allowed to produce side effects.

However:

- side effects must be explicit and intentional
- steps must not perform hidden or implicit changes
- external interactions must be delegated to providers

This keeps side effects observable and testable.

---

## Usage

### Writing steps

When writing a new step, authors should:

- keep the responsibility narrow and focused
- rely only on documented provider contracts
- emit meaningful events for observability
- respect idempotency expectations
- avoid embedding configuration or environment assumptions

### Steps and configuration

Configuration supplies **parameters** to steps.
It must not replace step logic.

Steps should:

- interpret configuration declaratively
- validate required inputs
- remain functional across environments

### Steps and providers

Steps interact with external systems exclusively through providers.

Steps must not:

- access infrastructure directly
- assume provider implementation details
- embed credentials or environment-specific values

## Inputs

Steps receive inputs from the workflow under `Inputs` and may reference:

- `Request.*`
- `State.*`
- `Policy.*` (optional root, host-defined)

### Security: Data-only constraint

**All step inputs must be data-only and must not contain ScriptBlocks.**

The engine enforces this before a handler runs: workflow definitions and plans are scanned with
`Assert-IdleNoScriptBlock`, and `With` is validated against the step's `WithSchema`. Handlers do not repeat these checks.

If a step processes other untrusted data (for example values read from a request at execution time), validate it
with the centralized helper instead of custom ScriptBlock checks:

```powershell
Assert-IdleNoScriptBlock -InputObject $value -Path 'Request.Context.Something'
```

---

## Outputs

Steps may write to `State.*` only, and only to declared output paths.
This prevents hidden coupling between steps.

### Eventing

Steps may emit **structured events** for progress and audit.

The engine provides a stable, object-based contract on the execution context:

- `Context.EventSink.WriteEvent(Type, Message, StepName, Data[, Level])`

Notes:

- `Type` says *what happened*: `IdLE.<Area>.<Event>` for first-party steps (e.g. `IdLE.Step.DirectorySync.Completed`),
  `<Owner>.IdLE.<Area>.<Event>` for extensions (e.g. `Contoso.IdLE.Hr.ManagerSynced`).
  See [Event types](events.md#event-types).
- `Message` is a human-readable message.
- `StepName` should be the current step name (if available).
- `Data` is an optional hashtable for structured details.
- `Level` says *how severe* it is: `Information` (default), `Warning` or `Error`.

Example:

```powershell
$Context.EventSink.WriteEvent(
  'Contoso.IdLE.Hr.ManagerSynced',
  'Synced manager from HR.',
  $Step.Name,
  @{ Provider = 'Identity'; Attribute = 'Manager' }
)
```

- Steps must never execute code from configuration.
- Steps must not assume a specific host UI.
- Hosts can optionally stream events via `Invoke-IdlePlan -EventSink <object>`,
  but **ScriptBlock sinks are not supported**.

---

## Error behavior

### Primary steps (fail-fast)

IdLE uses a **fail-fast execution model** for primary workflow steps:

- A failing step stops plan execution immediately
- Subsequent primary steps are not executed
- Results and events capture what happened up to the failure

### OnFailureSteps (best-effort)

When primary steps fail, workflows can define **OnFailureSteps** for cleanup or rollback.

OnFailureSteps are executed in **best-effort mode**:

- Each OnFailure step is attempted regardless of previous OnFailure step failures
- OnFailure step failures do not stop execution of remaining OnFailure steps
- The overall execution status remains 'Failed' even if all OnFailure steps succeed

**Execution result structure:**

```powershell
$result.Status                # 'Failed' when primary steps fail
$result.Steps                 # Array of primary step results (only executed steps)
$result.OnFailure.Status      # 'NotRun', 'Completed', or 'PartiallyFailed'
$result.OnFailure.Steps       # Array of OnFailure step results
```

**OnFailure status values:**

- `NotRun`: No primary steps failed, OnFailure steps were not executed
- `Completed`: All OnFailure steps succeeded
- `PartiallyFailed`: At least one OnFailure step failed, but execution continued

For details on declaring OnFailureSteps, see [Workflows](../use/workflows.md).

### Blocked outcome (runtime preconditions)

A step may produce a `Blocked` outcome when a **runtime precondition** fails at execution time.

`Blocked` is a first-class outcome distinct from `Failed`:

- `Blocked` represents a **policy/safety gate**, not a technical error.
- Execution stops immediately (subsequent steps are not run).
- `OnFailureSteps` do **not** run for a `Blocked` outcome.
- `result.Status` is `'Blocked'`; `result.OnFailure.Status` is `'NotRun'`.

For details on configuring runtime preconditions, see
[Runtime Preconditions](../use/preconditions.md).

---

## Common pitfalls

### Overloading steps

Steps that attempt to do too much:

- become hard to test
- blur responsibility boundaries
- reduce reuse

Prefer composing multiple focused steps instead.

### Encoding logic in configuration

Complex logic does not belong in configuration.

If a workflow becomes hard to read, the logic likely belongs in a step.

### Ignoring metadata

Undocumented behavior leads to:

- fragile steps
- unclear reviews
- broken expectations

Metadata is not optional; it is part of the step contract.

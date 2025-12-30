# Step Catalog

> Generated file. Do not edit by hand.
> Source: tools/Generate-IdleStepReference.ps1 — 2025-12-30 20:19:42 UTC

This page documents built-in IdLE steps discovered from `Invoke-IdleStep*` functions in `IdLE.Steps.*` modules.

---

### EmitEvent

- **Step Name**: $stepType
- **Implementation**: $commandName
- **Idempotent**: $idempotent
- **Contracts**: $contracts
- **Events**: Unknown

**Synopsis**

Emits a custom event (demo step).

**Description**

This step does not change external state. It emits a custom event message.
The engine provides an EventSink on the execution context that the step can use
to write structured events.

**Inputs (With.\*)**

_Unknown (not detected automatically). Document required With.* keys in the step help and/or use a supported pattern._


---

### EnsureAttribute

- **Step Name**: $stepType
- **Implementation**: $commandName
- **Idempotent**: $idempotent
- **Contracts**: $contracts
- **Events**: Unknown

**Synopsis**

Ensures that an identity attribute matches the desired value.

**Description**

This is a provider-agnostic step. The host must supply a provider instance via
Context.Providers[<ProviderAlias>]. The provider must implement an EnsureAttribute
method with the signature (IdentityKey, Name, Value) and return an object that
contains a boolean property 'Changed'.

The step is idempotent by design: it converges state to the desired value.

**Inputs (With.\*)**

| Key | Required |
|---|---|
| $k | Yes |
| $k | Yes |
| $k | Yes |


---


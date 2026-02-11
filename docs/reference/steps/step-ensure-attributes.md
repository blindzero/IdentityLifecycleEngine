# IdLE.Step.EnsureAttributes

> Generated file. Do not edit by hand.
> Source: tools/Generate-IdleStepReference.ps1

## Summary

- **Step Type**: `IdLE.Step.EnsureAttributes`
- **Module**: `IdLE.Steps.Common`
- **Implementation**: `Invoke-IdleStepEnsureAttributes`
- **Idempotent**: `Yes`

## Synopsis

Ensures that multiple identity attributes match their desired values.

## Description

This is a provider-agnostic step that can ensure multiple attributes in a single step.
The host must supply a provider instance via Context.Providers[&lt;ProviderAlias&gt;].

Provider interaction strategy:

1. If the provider implements EnsureAttributes(IdentityKey, AttributesHashtable), it is called once (fast path).

2. Otherwise, the step falls back to calling EnsureAttribute(IdentityKey, Name, Value) for each attribute.

The step is idempotent by design: it converges state to the desired values.

Authentication:

- If With.AuthSessionName is present, the step acquires an auth session via
  Context.AcquireAuthSession(Name, Options) and passes it to the provider method
  if the provider supports an AuthSession parameter.

- With.AuthSessionOptions (optional, hashtable) is passed to the broker for
  session selection (e.g., @\{ Role = 'Tier0' \}).

- ScriptBlocks in AuthSessionOptions are rejected (security boundary).

## Inputs (With.*)

The following keys are required in the step's ``With`` configuration:

| Key | Required | Description |
| --- | --- | --- |
| `Attributes` | Yes | Hashtable of attributes to set |
| `IdentityKey` | Yes | Unique identifier for the identity |

## Example

```powershell
@{
  Name = 'IdLE.Step.EnsureAttributes Example'
  Type = 'IdLE.Step.EnsureAttributes'
  With = @{
    Attributes           = @{ GivenName = 'First'; Surname = 'Last' }
    IdentityKey          = 'user.name'
  }
}
```

## See Also

- [Capabilities Reference](../capabilities.md) - Overview of IdLE capabilities
- [Providers](../providers.md) - Available provider implementations

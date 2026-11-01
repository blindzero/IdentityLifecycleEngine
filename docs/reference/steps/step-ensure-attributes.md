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
The engine passes the provider resolved from With.Provider (default 'Identity') as -Provider.

Provider interaction strategy:

1. If the provider implements EnsureAttributes(IdentityKey, AttributesHashtable), it is called once (fast path).

2. Otherwise, the step falls back to calling EnsureAttribute(IdentityKey, Name, Value) for each attribute.

The step is idempotent by design: it converges state to the desired values.

Authentication is handled by the engine (With.AuthSessionName, With.AuthSessionOptions).

## Inputs (With.*)

Validated at plan time against the step's ``WithSchema`` (see [Step metadata contract](../../extend/steps.md#step-metadata-contract)).

| Key | Type | Required | Default | Notes |
| --- | --- | --- | --- | --- |
| `Attributes` | Hashtable | Yes |  |  |
| `IdentityKey` | String | Yes |  |  |
| `AuthSessionName` | String | No | broker default session | Auth session routing key for the AuthSessionBroker. |
| `AuthSessionOptions` | Hashtable | No |  | Data-only options passed to the AuthSessionBroker. |
| `Provider` | String | No | `Identity` | Provider alias in `Providers`. |

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

# IdLE.Step.DeleteIdentity

> Generated file. Do not edit by hand.
> Source: tools/Generate-IdleStepReference.ps1

## Summary

- **Step Type**: `IdLE.Step.DeleteIdentity`
- **Module**: `IdLE.Steps.Common`
- **Implementation**: `Invoke-IdleStepDeleteIdentity`
- **Idempotent**: `Yes`

## Synopsis

Deletes an identity from the target system.

## Description

The engine passes the provider resolved from With.Provider (default 'Identity') as -Provider.
The provider implements DeleteIdentity(identityKey)
and returns an object with properties 'IdentityKey' and 'Changed'.

The step is idempotent by design: if the identity is already deleted, the provider
should return Changed = $false.

IMPORTANT: This step requires the provider to advertise the IdLE.Identity.Delete
capability, which is typically opt-in for safety. The provider must be configured
to allow deletion (e.g., AllowDelete = $true for AD provider).

Authentication is handled by the engine: With.AuthSessionName and With.AuthSessionOptions select the
auth session passed to provider methods that declare an AuthSession parameter.

## Inputs (With.*)

Validated at plan time against the step's ``WithSchema`` (see [Step metadata contract](../../extend/steps.md#step-metadata-contract)).

| Key | Type | Required | Default | Notes |
| --- | --- | --- | --- | --- |
| `IdentityKey` | String | Yes |  |  |
| `AuthSessionName` | String | No | broker default session | Auth session routing key for the AuthSessionBroker. |
| `AuthSessionOptions` | Hashtable | No |  | Data-only options passed to the AuthSessionBroker. |
| `Provider` | String | No | `Identity` | Provider alias in `Providers`. |

## Example

```powershell
@{
  Name = 'IdLE.Step.DeleteIdentity Example'
  Type = 'IdLE.Step.DeleteIdentity'
  With = @{
    IdentityKey          = 'user.name'
  }
}
```

## See Also

- [Capabilities Reference](../capabilities.md) - Overview of IdLE capabilities
- [Providers](../providers.md) - Available provider implementations

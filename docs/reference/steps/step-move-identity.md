# IdLE.Step.MoveIdentity

> Generated file. Do not edit by hand.
> Source: tools/Generate-IdleStepReference.ps1

## Summary

- **Step Type**: `IdLE.Step.MoveIdentity`
- **Module**: `IdLE.Steps.Common`
- **Implementation**: `Invoke-IdleStepMoveIdentity`
- **Idempotent**: `Yes`
- **Required Capabilities**: `IdLE.Identity.Move`

## Synopsis

Moves an identity to a different container/OU in the target system.

## Description

The engine passes the provider resolved from With.Provider (default 'Identity') as -Provider.
The provider implements MoveIdentity(identityKey, targetContainer)
and returns an object with properties 'IdentityKey' and 'Changed'.

The step is idempotent by design: if the identity is already in the target container,
the provider should return Changed = $false.

Authentication is handled by the engine: With.AuthSessionName and With.AuthSessionOptions select the
auth session passed to provider methods that declare an AuthSession parameter.

## Inputs (With.*)

Validated at plan time against the step's ``WithSchema`` (see [Step metadata contract](../../extend/steps.md#step-metadata-contract)).

| Key | Type | Required | Default | Notes |
| --- | --- | --- | --- | --- |
| `IdentityKey` | String | Yes |  |  |
| `TargetContainer` | String | Yes |  |  |
| `AuthSessionName` | String | No | broker default session | Auth session routing key for the AuthSessionBroker. |
| `AuthSessionOptions` | Hashtable | No |  | Data-only options passed to the AuthSessionBroker. |
| `Provider` | String | No | `Identity` | Provider alias in `Providers`. |

## Example

```powershell
@{
  Name = 'IdLE.Step.MoveIdentity Example'
  Type = 'IdLE.Step.MoveIdentity'
  With = @{
    IdentityKey          = 'user.name'
    TargetContainer      = '<value>'
  }
}
```

## See Also

- [Capabilities Reference](../capabilities.md) - Details on required capabilities
- [Providers](../providers.md) - Available provider implementations

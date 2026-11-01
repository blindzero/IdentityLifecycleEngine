# IdLE.Step.EnsureEntitlement

> Generated file. Do not edit by hand.
> Source: tools/Generate-IdleStepReference.ps1

## Summary

- **Step Type**: `IdLE.Step.EnsureEntitlement`
- **Module**: `IdLE.Steps.Common`
- **Implementation**: `Invoke-IdleStepEnsureEntitlement`
- **Idempotent**: `Yes`

## Synopsis

Ensures that an entitlement assignment is present or absent for an identity.

## Description

This provider-agnostic step uses entitlement provider contracts to converge
an assignment to the desired state. The engine passes the provider resolved from With.Provider (default 'Identity')
as -Provider. The provider implements:

- ListEntitlements(identityKey)

- GrantEntitlement(identityKey, entitlement)

- RevokeEntitlement(identityKey, entitlement)

The step is idempotent and only calls Grant/Revoke when the assignment needs
to change.

Authentication is handled by the engine (With.AuthSessionName, With.AuthSessionOptions).

## Inputs (With.*)

Validated at plan time against the step's ``WithSchema`` (see [Step metadata contract](../../extend/steps.md#step-metadata-contract)).

| Key | Type | Required | Default | Notes |
| --- | --- | --- | --- | --- |
| `Entitlement` | Hashtable | Yes |  | Keys: `DisplayName`, `Id` (required), `Kind` (required) |
| `IdentityKey` | String | Yes |  |  |
| `State` | String | No | `Present` | One of: `Present`, `Absent` |
| `AuthSessionName` | String | No | broker default session | Auth session routing key for the AuthSessionBroker. |
| `AuthSessionOptions` | Hashtable | No |  | Data-only options passed to the AuthSessionBroker. |
| `Provider` | String | No | `Identity` | Provider alias in `Providers`. |

## Example

```powershell
@{
    Name = 'Ensure group access'
    Type = 'IdLE.Step.EnsureEntitlement'
    With = @{
        IdentityKey = 'user1'
        Entitlement = @{ Kind = 'Group'; Id = 'example-group' }
        State       = 'Present'
    }
}
```

## See Also

- [Capabilities Reference](../capabilities.md) - Overview of IdLE capabilities
- [Providers](../providers.md) - Available provider implementations

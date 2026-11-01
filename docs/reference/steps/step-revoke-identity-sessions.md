# IdLE.Step.RevokeIdentitySessions

> Generated file. Do not edit by hand.
> Source: tools/Generate-IdleStepReference.ps1

## Summary

- **Step Type**: `IdLE.Step.RevokeIdentitySessions`
- **Module**: `IdLE.Steps.Common`
- **Implementation**: `Invoke-IdleStepRevokeIdentitySessions`
- **Idempotent**: `Unknown`

## Synopsis

Revokes all active sign-in sessions for an identity in the target system.

## Description

This is a provider-agnostic step that revokes active sign-in sessions (refresh tokens)
for a given identity. The engine passes the provider resolved from With.Provider (default 'Identity') as -Provider.
The provider implements RevokeSessions(identityKey)
and returns an object with properties 'IdentityKey' and 'Changed'.

This step is typically used in Leaver workflows after disabling an identity to ensure
that existing sessions are terminated immediately, rather than waiting for tokens to expire.

The step does not modify the identity itself (e.g., does not disable the account).
Use IdLE.Step.DisableIdentity separately if account disabling is also required.

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
# In a workflow definition (PSD1):
@{
    Name = 'Revoke Entra sessions'
    Type = 'IdLE.Step.RevokeIdentitySessions'
    With = @{
        Provider = 'Entra'
        IdentityKey = 'max.power@contoso.com'
        AuthSessionName = 'MicrosoftGraph'
        AuthSessionOptions = @{ Role = 'Admin' }
    }
}
```

## See Also

- [Capabilities Reference](../capabilities.md) - Overview of IdLE capabilities
- [Providers](../providers.md) - Available provider implementations

# IdLE.Step.Mailbox.EnsureType

> Generated file. Do not edit by hand.
> Source: tools/Generate-IdleStepReference.ps1

## Summary

- **Step Type**: `IdLE.Step.Mailbox.EnsureType`
- **Module**: `IdLE.Steps.Mailbox`
- **Implementation**: `Invoke-IdleStepMailboxTypeEnsure`
- **Idempotent**: `Yes`
- **Required Capabilities**: `IdLE.Mailbox.Info.Read`, `IdLE.Mailbox.Type.Ensure`

## Synopsis

Ensures that a mailbox is of the desired type (User, Shared, Room, Equipment).

## Description

The engine passes the provider resolved from With.Provider
(default 'ExchangeOnline') as -Provider. The provider implements an EnsureMailboxType
method with the signature (IdentityKey, MailboxType, AuthSession) and return an object
that contains a boolean property 'Changed'.

The step is idempotent by design: it converges state to the desired type.

Supported mailbox types:

- User (regular user mailbox)

- Shared (shared mailbox for team use)

- Room (room resource mailbox)

- Equipment (equipment resource mailbox)

Authentication is handled by the engine: without With.AuthSessionName the session is named after the
provider alias (e.g. 'ExchangeOnline'); With.AuthSessionOptions is passed to the broker.

## Inputs (With.*)

Validated at plan time against the step's ``WithSchema`` (see [Step metadata contract](../../extend/steps.md#step-metadata-contract)).

| Key | Type | Required | Default | Notes |
| --- | --- | --- | --- | --- |
| `IdentityKey` | String | Yes |  |  |
| `MailboxType` | String | Yes |  | One of: `User`, `Shared`, `Room`, `Equipment` |
| `AuthSessionName` | String | No | provider alias | Auth session routing key for the AuthSessionBroker. |
| `AuthSessionOptions` | Hashtable | No |  | Data-only options passed to the AuthSessionBroker. |
| `Provider` | String | No | `ExchangeOnline` | Provider alias in `Providers`. |

## Example

```powershell
# In workflow definition (convert to shared mailbox):
@{
    Name = 'Convert to shared mailbox'
    Type = 'IdLE.Step.Mailbox.EnsureType'
    With = @{
        Provider    = 'ExchangeOnline'
        IdentityKey = 'user@contoso.com'
        MailboxType = 'Shared'
    }
}
```

## See Also

- [Capabilities Reference](../capabilities.md) - Details on required capabilities
- [Providers](../providers.md) - Available provider implementations

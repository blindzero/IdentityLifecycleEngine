# IdLE.Step.Mailbox.GetInfo

> Generated file. Do not edit by hand.
> Source: tools/Generate-IdleStepReference.ps1

## Summary

- **Step Type**: `IdLE.Step.Mailbox.GetInfo`
- **Module**: `IdLE.Steps.Mailbox`
- **Implementation**: `Invoke-IdleStepMailboxGetInfo`
- **Idempotent**: `Unknown`

## Synopsis

Retrieves mailbox details and returns a structured report.

## Description

The engine passes the provider resolved from With.Provider
(default 'ExchangeOnline') as -Provider. The provider implements a GetMailbox
method with the signature (IdentityKey, AuthSession) and return a mailbox object.

The step is read-only and returns Changed = $false.

Authentication is handled by the engine: without With.AuthSessionName the session is named after the
provider alias (e.g. 'ExchangeOnline'); With.AuthSessionOptions is passed to the broker.

## Inputs (With.*)

Validated at plan time against the step's ``WithSchema`` (see [Step metadata contract](../../extend/steps.md#step-metadata-contract)).

| Key | Type | Required | Default | Notes |
| --- | --- | --- | --- | --- |
| `IdentityKey` | String | Yes |  |  |
| `AuthSessionName` | String | No | provider alias | Auth session routing key for the AuthSessionBroker. |
| `AuthSessionOptions` | Hashtable | No |  | Data-only options passed to the AuthSessionBroker. |
| `Provider` | String | No | `ExchangeOnline` | Provider alias in `Providers`. |

## Example

```powershell
# In workflow definition:
@{
    Name = 'Get mailbox info'
    Type = 'IdLE.Step.Mailbox.GetInfo'
    With = @{
        Provider      = 'ExchangeOnline'
        IdentityKey   = 'user@contoso.com'
    }
}
```

## See Also

- [Capabilities Reference](../capabilities.md) - Overview of IdLE capabilities
- [Providers](../providers.md) - Available provider implementations

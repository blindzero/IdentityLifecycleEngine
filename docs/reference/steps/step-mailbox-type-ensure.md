# MailboxTypeEnsure

> Generated file. Do not edit by hand.
> Source: tools/Generate-IdleStepReference.ps1

## Summary

- **Step Type**: `MailboxTypeEnsure`
- **Module**: `IdLE.Steps.Mailbox`
- **Implementation**: `Invoke-IdleStepMailboxTypeEnsure`
- **Idempotent**: `Yes`

## Synopsis

Ensures that a mailbox is of the desired type (User, Shared, Room, Equipment).

## Description

The host must supply a provider instance via
Context.Providers[&lt;ProviderAlias&gt;]. The provider must implement an EnsureMailboxType
method with the signature (IdentityKey, MailboxType, AuthSession) and return an object
that contains a boolean property 'Changed'.

The step is idempotent by design: it converges state to the desired type.

Supported mailbox types:

- User (regular user mailbox)

- Shared (shared mailbox for team use)

- Room (room resource mailbox)

- Equipment (equipment resource mailbox)

Authentication:

- If With.AuthSessionName is present, the step acquires an auth session via
  Context.AcquireAuthSession(Name, Options) and passes it to the provider method.

- If With.AuthSessionName is absent, defaults to With.Provider value (e.g., 'ExchangeOnline').

- With.AuthSessionOptions (optional, hashtable) is passed to the broker for
  session selection (e.g., @\{ Role = 'Admin' \}).

## Inputs (With.*)

The following keys are required in the step's ``With`` configuration:

| Key | Required | Description |
| --- | --- | --- |
| `IdentityKey` | Yes | Unique identifier for the identity |
| `MailboxType` | Yes | See step description for details |

## Example

```powershell
@{
  Name = 'MailboxTypeEnsure Example'
  Type = 'IdLE.Step.MailboxTypeEnsure'
  With = @{
    IdentityKey          = 'user.name'
    MailboxType          = '<value>'
  }
}
```

## See Also

- [Capabilities Reference](../capabilities.md) - Overview of IdLE capabilities
- [Providers](../providers.md) - Available provider implementations

# MailboxGetInfo

> Generated file. Do not edit by hand.
> Source: tools/Generate-IdleStepReference.ps1

## Summary

- **Step Type**: `MailboxGetInfo`
- **Module**: `IdLE.Steps.Mailbox`
- **Implementation**: `Invoke-IdleStepMailboxGetInfo`
- **Idempotent**: `Unknown`

## Synopsis

Retrieves mailbox details and returns a structured report.

## Description

The host must supply a provider instance via
Context.Providers[&lt;ProviderAlias&gt;]. The provider must implement a GetMailbox
method with the signature (IdentityKey, AuthSession) and return a mailbox object.

The step is read-only and returns Changed = $false.

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

## Example

```powershell
@{
  Name = 'MailboxGetInfo Example'
  Type = 'IdLE.Step.Mailbox.GetInfo'
  With = @{
    IdentityKey          = 'user.name'
  }
}
```

## See Also

- [Capabilities Reference](../capabilities.md) - Overview of IdLE capabilities
- [Providers](../providers.md) - Available provider implementations

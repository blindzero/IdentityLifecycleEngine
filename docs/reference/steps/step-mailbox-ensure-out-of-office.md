# IdLE.Step.Mailbox.EnsureOutOfOffice

> Generated file. Do not edit by hand.
> Source: tools/Generate-IdleStepReference.ps1

## Summary

- **Step Type**: `IdLE.Step.Mailbox.EnsureOutOfOffice`
- **Module**: `IdLE.Steps.Mailbox`
- **Implementation**: `Invoke-IdleStepMailboxOutOfOfficeEnsure`
- **Idempotent**: `Yes`

## Synopsis

Ensures that a mailbox Out of Office (OOF) configuration matches the desired state.

## Description

The host must supply a provider instance via
Context.Providers[&lt;ProviderAlias&gt;]. The provider must implement an EnsureOutOfOffice
method with the signature (IdentityKey, Config, AuthSession) and return an object
that contains a boolean property 'Changed'.

The step is idempotent by design: it converges OOF configuration to the desired state.

Out of Office Config shape (data-only hashtable):

- Mode: 'Disabled' | 'Enabled' | 'Scheduled' (required)

- Start: DateTime (required when Mode = 'Scheduled')

- End: DateTime (required when Mode = 'Scheduled')

- InternalMessage: string (optional)

- ExternalMessage: string (optional)

- ExternalAudience: 'None' | 'Known' | 'All' (optional, default provider-specific)

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
| `Config` | Yes | See step description for details |
| `IdentityKey` | Yes | Unique identifier for the identity |

## Example

```powershell
@{
  Name = 'IdLE.Step.Mailbox.EnsureOutOfOffice Example'
  Type = 'IdLE.Step.Mailbox.EnsureOutOfOffice'
  With = @{
    Config               = '<value>'
    IdentityKey          = 'user.name'
  }
}
```

## See Also

- [Capabilities Reference](../capabilities.md) - Overview of IdLE capabilities
- [Providers](../providers.md) - Available provider implementations

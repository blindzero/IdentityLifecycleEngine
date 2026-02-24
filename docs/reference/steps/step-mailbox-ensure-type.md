# IdLE.Step.Mailbox.EnsureType

> Generated file. Do not edit by hand.
> Source: tools/Generate-IdleStepReference.ps1

## Summary

- **Step Type**: `IdLE.Step.Mailbox.EnsureType`
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

The following keys are supported in the step's ``With`` configuration:

| Key | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `IdentityKey` | `string` | Yes | — | UPN, SMTP address, or other identity key recognized by the provider. Supports ``\{\{Request.*\}\}`` template expressions. |
| `MailboxType` | `string` | Yes | — | Desired mailbox type: ``User`` \| ``Shared`` \| ``Room`` \| ``Equipment``. |
| `Provider` | `string` | No | Step-specific | Provider alias key in the providers map supplied at runtime. |
| `AuthSessionName` | `string` | No | ``Provider`` value | Auth session name passed to ``Context.AcquireAuthSession()``. Defaults to the ``Provider`` value. |
| `AuthSessionOptions` | `hashtable` | No | ``$null`` | Data-only options passed to the auth session broker (e.g., ``@\{ Role = 'Admin' \}``). ScriptBlocks are rejected. |

## Examples

### Example 1 — In workflow definition (convert to shared mailbox)

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

- [Capabilities Reference](../capabilities.md) - Overview of IdLE capabilities
- [Providers](../providers.md) - Available provider implementations

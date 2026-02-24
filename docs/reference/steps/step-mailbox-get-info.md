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

The following keys are supported in the step's ``With`` configuration:

| Key | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `IdentityKey` | `string` | Yes | — | UPN, SMTP address, or other identity key recognized by the provider. Supports ``\{\{Request.*\}\}`` template expressions. |
| `Provider` | `string` | No | Step-specific | Provider alias key in the providers map supplied at runtime. |
| `AuthSessionName` | `string` | No | ``Provider`` value | Auth session name passed to ``Context.AcquireAuthSession()``. Defaults to the ``Provider`` value. |
| `AuthSessionOptions` | `hashtable` | No | ``$null`` | Data-only options passed to the auth session broker (e.g., ``@\{ Role = 'Admin' \}``). ScriptBlocks are rejected. |

## Examples

### Example 1 — In workflow definition

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

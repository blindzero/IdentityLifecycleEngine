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
for a given identity. The host must supply a provider instance via
Context.Providers[&lt;ProviderAlias&gt;] that implements RevokeSessions(identityKey)
and returns an object with properties 'IdentityKey' and 'Changed'.

This step is typically used in Leaver workflows after disabling an identity to ensure
that existing sessions are terminated immediately, rather than waiting for tokens to expire.

The step does not modify the identity itself (e.g., does not disable the account).
Use IdLE.Step.DisableIdentity separately if account disabling is also required.

Authentication:

- If With.AuthSessionName is present, the step acquires an auth session via
  Context.AcquireAuthSession(Name, Options) and passes it to the provider method
  if the provider supports an AuthSession parameter.

- With.AuthSessionOptions (optional, hashtable) is passed to the broker for
  session selection (e.g., @\{ Role = 'Tier0' \}).

- ScriptBlocks in AuthSessionOptions are rejected (security boundary).

## Inputs (With.*)

The following keys are supported in the step's ``With`` configuration:

| Key | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `IdentityKey` | `string` | Yes | — | UPN, SMTP address, or other identity key recognized by the provider. Supports ``\{\{Request.*\}\}`` template expressions. |
| `Provider` | `string` | No | Step-specific | Provider alias key in the providers map supplied at runtime. |
| `AuthSessionName` | `string` | No | ``Provider`` value | Auth session name passed to ``Context.AcquireAuthSession()``. Defaults to the ``Provider`` value. |
| `AuthSessionOptions` | `hashtable` | No | ``$null`` | Data-only options passed to the auth session broker (e.g., ``@\{ Role = 'Admin' \}``). ScriptBlocks are rejected. |

## Examples

### Example 1 — In a workflow definition (PSD1)

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

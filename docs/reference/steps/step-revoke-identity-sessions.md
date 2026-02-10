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

The following keys are required in the step's ``With`` configuration:

| Key | Required | Description |
| --- | --- | --- |
| `IdentityKey` | Yes | Unique identifier for the identity |

## Example

```powershell
@{
  Name = 'IdLE.Step.RevokeIdentitySessions Example'
  Type = 'IdLE.Step.RevokeIdentitySessions'
  With = @{
    IdentityKey          = 'user.name'
  }
}
```

## See Also

- [Capabilities Reference](../capabilities.md) - Overview of IdLE capabilities
- [Providers](../providers.md) - Available provider implementations

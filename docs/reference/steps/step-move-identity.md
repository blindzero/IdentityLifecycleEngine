# IdLE.Step.MoveIdentity

> Generated file. Do not edit by hand.
> Source: tools/Generate-IdleStepReference.ps1

## Summary

- **Step Type**: `IdLE.Step.MoveIdentity`
- **Module**: `IdLE.Steps.Common`
- **Implementation**: `Invoke-IdleStepMoveIdentity`
- **Idempotent**: `Yes`

## Synopsis

Moves an identity to a different container/OU in the target system.

## Description

The host must supply a provider instance via
Context.Providers[&lt;ProviderAlias&gt;] that implements MoveIdentity(identityKey, targetContainer)
and returns an object with properties 'IdentityKey' and 'Changed'.

The step is idempotent by design: if the identity is already in the target container,
the provider should return Changed = $false.

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
| `TargetContainer` | `string` | Yes | — | See step description for details. |
| `Provider` | `string` | No | Step-specific | Provider alias key in the providers map supplied at runtime. |
| `AuthSessionName` | `string` | No | ``Provider`` value | Auth session name passed to ``Context.AcquireAuthSession()``. Defaults to the ``Provider`` value. |
| `AuthSessionOptions` | `hashtable` | No | ``$null`` | Data-only options passed to the auth session broker (e.g., ``@\{ Role = 'Admin' \}``). ScriptBlocks are rejected. |

## Example

```powershell
@{
  Name = 'IdLE.Step.MoveIdentity Example'
  Type = 'IdLE.Step.MoveIdentity'
  With = @{
    IdentityKey          = 'user@contoso.com'
    TargetContainer      = '<value>'
  }
}
```

## See Also

- [Capabilities Reference](../capabilities.md) - Overview of IdLE capabilities
- [Providers](../providers.md) - Available provider implementations

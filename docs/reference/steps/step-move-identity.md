# MoveIdentity

> Generated file. Do not edit by hand.
> Source: tools/Generate-IdleStepReference.ps1

## Summary

- **Step Type**: `MoveIdentity`
- **Module**: `IdLE.Steps.Common`
- **Implementation**: `Invoke-IdleStepMoveIdentity`
- **Idempotent**: `Yes`
- **Required Capabilities**: `IdLE.Identity.Move`

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

The following keys are required in the step's ``With`` configuration:

| Key | Required | Description |
| --- | --- | --- |
| `IdentityKey` | Yes | Unique identifier for the identity |
| `TargetContainer` | Yes | See step description for details |

## Example

```powershell
@{
  Name = 'MoveIdentity Example'
  Type = 'IdLE.Step.MoveIdentity'
  With = @{
    IdentityKey          = 'user.name'
    TargetContainer      = '<value>'
  }
}
```

## See Also

- [Capabilities Reference](../capabilities.md) - Details on required capabilities
- [Providers](../providers.md) - Available provider implementations

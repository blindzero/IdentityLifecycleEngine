# EnsureEntitlement

> Generated file. Do not edit by hand.
> Source: tools/Generate-IdleStepReference.ps1

## Summary

- **Step Type**: `EnsureEntitlement`
- **Module**: `IdLE.Steps.Common`
- **Implementation**: `Invoke-IdleStepEnsureEntitlement`
- **Idempotent**: `Yes`
- **Required Capabilities**: `IdLE.Entitlement.List`, `IdLE.Entitlement.Grant`, `IdLE.Entitlement.Revoke`

## Synopsis

Ensures that an entitlement assignment is present or absent for an identity.

## Description

This provider-agnostic step uses entitlement provider contracts to converge
an assignment to the desired state. The host must supply a provider instance
via `Context.Providers[&lt;ProviderAlias&gt;]` that implements:

- ListEntitlements(identityKey)

- GrantEntitlement(identityKey, entitlement)

- RevokeEntitlement(identityKey, entitlement)

The step is idempotent and only calls Grant/Revoke when the assignment needs
to change.

Authentication:

- If With.AuthSessionName is present, the step acquires an auth session via
  Context.AcquireAuthSession(Name, Options) and passes it to the provider methods
  if the provider supports an AuthSession parameter.

- With.AuthSessionOptions (optional, hashtable) is passed to the broker for
  session selection (e.g., @\{ Role = 'Tier0' \}).

- ScriptBlocks in AuthSessionOptions are rejected (security boundary).

## Inputs (With.*)

The following keys are required in the step's ``With`` configuration:

| Key | Required | Description |
| --- | --- | --- |
| `IdentityKey` | Yes | Unique identifier for the identity |
| `Entitlement` | Yes | Entitlement identifier or object |
| `State` | Yes | Desired state for the entitlement |

## Example

```powershell
@{
  Name = 'EnsureEntitlement Example'
  Type = 'IdLE.Step.EnsureEntitlement'
  With = @{
    IdentityKey          = 'user.name'
    Entitlement          = @{ Type = 'Group'; Value = 'GroupId' }
    State                = 'Present'
  }
}
```

## See Also

- [Capabilities Reference](../capabilities.md) - Details on required capabilities
- [Providers](../providers.md) - Available provider implementations

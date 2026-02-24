# IdLE.Step.EnsureEntitlement

> Generated file. Do not edit by hand.
> Source: tools/Generate-IdleStepReference.ps1

## Summary

- **Step Type**: `IdLE.Step.EnsureEntitlement`
- **Module**: `IdLE.Steps.Common`
- **Implementation**: `Invoke-IdleStepEnsureEntitlement`
- **Idempotent**: `Yes`

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

The following keys are supported in the step's ``With`` configuration:

| Key | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `Entitlement` | `hashtable` | Yes | — | Entitlement descriptor: ``Kind`` (string), ``Id`` (string), optional ``DisplayName`` (string). |
| `IdentityKey` | `string` | Yes | — | UPN, SMTP address, or other identity key recognized by the provider. Supports ``\{\{Request.*\}\}`` template expressions. |
| `State` | `string` | Yes | — | Desired assignment state: ``Present`` \| ``Absent``. |
| `Provider` | `string` | No | Step-specific | Provider alias key in the providers map supplied at runtime. |
| `AuthSessionName` | `string` | No | ``Provider`` value | Auth session name passed to ``Context.AcquireAuthSession()``. Defaults to the ``Provider`` value. |
| `AuthSessionOptions` | `hashtable` | No | ``$null`` | Data-only options passed to the auth session broker (e.g., ``@\{ Role = 'Admin' \}``). ScriptBlocks are rejected. |

## Examples

### Example 1

```powershell
Invoke-IdleStepEnsureEntitlement -Context $context -Step [pscustomobject]@{
    Name = 'Ensure group access'
    Type = 'IdLE.Step.EnsureEntitlement'
    With = @{
        IdentityKey = 'user1'
        Entitlement = @{ Kind = 'Group'; Id = 'example-group'; DisplayName = 'Example Group' }
        State       = 'Present'
        Provider    = 'Identity'
    }
}
```

## See Also

- [Capabilities Reference](../capabilities.md) - Overview of IdLE capabilities
- [Providers](../providers.md) - Available provider implementations

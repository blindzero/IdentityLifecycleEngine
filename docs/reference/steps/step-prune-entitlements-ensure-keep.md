# IdLE.Step.PruneEntitlementsEnsureKeep

> Generated file. Do not edit by hand.
> Source: tools/Generate-IdleStepReference.ps1

## Summary

- **Step Type**: `IdLE.Step.PruneEntitlementsEnsureKeep`
- **Module**: `IdLE.Steps.Common`
- **Implementation**: `Invoke-IdleStepPruneEntitlementsEnsureKeep`
- **Idempotent**: `Unknown`

## Synopsis

Converges an identity's entitlements by removing all non-kept entitlements and ensuring kept ones are present.

## Description

This provider-agnostic step implements "remove all except … and ensure those are present" semantics for
entitlements. It is intended for leaver and mover workflows where all entitlements of a given kind
(e.g. group memberships) must be removed except for an explicit keep-set, and the kept entitlements
must be guaranteed to be present.

This step always grants any explicit Keep items that are not yet present. Use IdLE.Step.PruneEntitlements
when you only need removal without the ensure-grant phase.

The host must supply a provider that:

- Advertises the IdLE.Entitlement.Prune capability (explicit opt-in)

- Implements ListEntitlements(identityKey)

- Implements RevokeEntitlement(identityKey, entitlement)

- Implements GrantEntitlement(identityKey, entitlement)

Provider/system non-removable entitlements (e.g., AD primary group / Domain Users) are
handled safely: if a revoke operation fails, the step emits a structured warning event,
skips the entitlement, and continues. The workflow is not failed for these items.

Authentication:

- If With.AuthSessionName is present, the step acquires an auth session via
  Context.AcquireAuthSession(Name, Options) and passes it to provider methods
  if the provider supports an AuthSession parameter.

- With.AuthSessionOptions (optional, hashtable) is passed to the broker for
  session selection (e.g., @\{ Role = 'Tier0' \}).

- ScriptBlocks in AuthSessionOptions are rejected (security boundary).

## Inputs (With.*)

The required input keys could not be detected automatically.
Please refer to the step description and examples for usage details.

## Example

```powershell
@{
  Name = 'IdLE.Step.PruneEntitlementsEnsureKeep Example'
  Type = 'IdLE.Step.PruneEntitlementsEnsureKeep'
  With = @{
    # See step description for available options
  }
}
```

## See Also

- [Capabilities Reference](../capabilities.md) - Overview of IdLE capabilities
- [Providers](../providers.md) - Available provider implementations

# IdLE.Step.PruneEntitlementsEnsureKeep

> Generated file. Do not edit by hand.
> Source: tools/Generate-IdleStepReference.ps1

## Summary

- **Step Type**: `IdLE.Step.PruneEntitlementsEnsureKeep`
- **Module**: `IdLE.Steps.Common`
- **Implementation**: `Invoke-IdleStepPruneEntitlementsEnsureKeep`
- **Idempotent**: `Yes`

## Synopsis

Converges an identity's entitlements by removing all non-kept entitlements and ensuring kept ones are present.

## Description

This provider-agnostic step combines "remove all except" semantics with "ensure kept entitlements are present".
It is intended for leaver and mover workflows where all entitlements of a given kind must be removed except
for an explicit keep-set, and where those kept entitlements must also be guaranteed to be present.

Use [`IdLE.Step.PruneEntitlements`](./step-prune-entitlements.md) when you only need removal without the
ensure-grant phase. Use this step type when you need both prune and grant semantics in a single operation.

The host must supply a provider that:

- Advertises the `IdLE.Entitlement.Prune` capability (explicit opt-in)
- Implements `ListEntitlements(identityKey)`
- Implements `RevokeEntitlement(identityKey, entitlement)`
- Implements `GrantEntitlement(identityKey, entitlement)`

Provider/system non-removable entitlements (e.g., AD primary group / Domain Users) are
handled safely: if a revoke operation fails, the step emits a structured warning event,
skips the entitlement, and continues. The workflow is not failed for these items.

Authentication:

- If `With.AuthSessionName` is present, the step acquires an auth session via
  `Context.AcquireAuthSession(Name, Options)` and passes it to provider methods
  if the provider supports an `AuthSession` parameter.
- `With.AuthSessionOptions` (optional, hashtable) is passed to the broker for
  session selection (e.g., `@{ Role = 'Tier0' }`).
- ScriptBlocks in `AuthSessionOptions` are rejected (security boundary).

## Inputs (With.*)

The following keys are supported in the step's `With` configuration:

| Key | Required | Description |
| --- | --- | --- |
| `IdentityKey` | Yes | Unique identifier for the identity whose entitlements to prune |
| `Kind` | Yes | Entitlement kind to prune (e.g. `Group`, `Role`, `License`) — provider-defined |
| `Keep` | No* | Array of entitlement references to keep. Each entry must have an `Id` and optionally a `Kind` and `DisplayName`. At least one of `Keep` or `KeepPattern` is required. Missing `Keep` items are granted. |
| `KeepPattern` | No* | Array of wildcard strings (PowerShell `-like` semantics). Current entitlements whose `Id` or `DisplayName` matches any pattern are kept. At least one of `Keep` or `KeepPattern` is required. Pattern-matched entitlements are never "ensured" — only explicit `Keep` items are granted. |
| `Provider` | No | Alias for the provider in `Context.Providers`. Defaults to `'Identity'`. |
| `AuthSessionName` | No | Name used to acquire an auth session via `Context.AcquireAuthSession(...)`. |
| `AuthSessionOptions` | No | Hashtable of options passed to the auth session broker (e.g., `@{ Role = 'Tier0' }`). ScriptBlocks are rejected. |

\* At least one of `Keep` or `KeepPattern` **must** be provided. Specifying neither is rejected as a safety guardrail.

## Capability Requirement

This step requires the provider to advertise the `IdLE.Entitlement.Prune` capability (explicit opt-in).
This is in addition to the standard `IdLE.Entitlement.List`, `IdLE.Entitlement.Revoke`, and
`IdLE.Entitlement.Grant` capabilities.

See [Capabilities Reference](../capabilities.md) for details.

## Behavior

The step executes the following convergence logic:

1. Lists all current entitlements of the specified `Kind` for the identity (single read).
2. Normalizes `Keep` item IDs to canonical form via `provider.NormalizeEntitlementId` (when available).
3. Builds a **keep-set** from:
   - Explicit `Keep` entries (matched by case-insensitive `Id` comparison after normalization)
   - Current entitlements whose `Id` or `DisplayName` matches any `KeepPattern` wildcard
4. Computes **remove-set** = current − keep-set.
5. Revokes each entitlement in the remove-set. If a revoke fails (e.g. non-removable entitlement), the error is recorded as a skip with a warning event; the workflow continues.
6. Grants any explicit `Keep` entitlements that were not in the current set (**ensure phase**). Pattern-matched entitlements are never ensured.

## Result

Returns an `IdLE.StepResult` object. In addition to the standard `Status`, `Changed`, and `Error` properties,
a `Skipped` array is included. Each entry in `Skipped` contains:

| Property | Description |
| --- | --- |
| `EntitlementId` | The `Id` of the entitlement that could not be removed |
| `Reason` | The error message from the provider |

## Examples

### Keep one explicit group and ensure it is present

```powershell
@{
  Name = 'Prune groups and ensure leaver group (leaver)'
  Type = 'IdLE.Step.PruneEntitlementsEnsureKeep'
  With = @{
    IdentityKey = '{{Request.Intent.SamAccountName}}'
    Kind        = 'Group'
    Keep        = @(
      @{ Kind = 'Group'; Id = 'CN=LEAVER-RETAIN,OU=Groups,DC=contoso,DC=com' }
    )
  }
}
```

### Keep + wildcard pattern and ensure the explicit leaver group is present

```powershell
@{
  Name      = 'Prune groups and ensure leaver group (leaver with pattern)'
  Type      = 'IdLE.Step.PruneEntitlementsEnsureKeep'
  Condition = @{ Equals = @{ Path = 'Request.Intent.PruneGroups'; Value = $true } }
  With      = @{
    IdentityKey     = '{{Request.Intent.SamAccountName}}'
    Provider        = 'Identity'
    Kind            = 'Group'
    Keep            = @(
      @{ Kind = 'Group'; Id = 'CN=LEAVER-RETAIN,OU=Groups,DC=contoso,DC=com'; DisplayName = 'Leaver Retain' }
    )
    KeepPattern     = @('CN=LEAVER-*,OU=Groups,DC=contoso,DC=com')
    AuthSessionName = 'Directory'
  }
}
```

## See Also

- [IdLE.Step.PruneEntitlements](./step-prune-entitlements.md) - Remove-only variant (no ensure phase)
- [Capabilities Reference](../capabilities.md) - Overview of IdLE capabilities including `IdLE.Entitlement.Prune`
- [Providers](../providers.md) - Available provider implementations
- [IdLE.Step.EnsureEntitlement](./step-ensure-entitlement.md) - Atomic single-entitlement convergence

# IdLE.Step.PruneEntitlementsEnsureKeep

> Generated file. Do not edit by hand.
> Source: tools/Generate-IdleStepReference.ps1

## Summary

- **Step Type**: `IdLE.Step.PruneEntitlementsEnsureKeep`
- **Module**: `IdLE.Steps.Common`
- **Implementation**: `Invoke-IdleStepPruneEntitlementsEnsureKeep`
- **Idempotent**: `Unknown`
- **Required Capabilities**: `IdLE.Entitlement.Prune`, `IdLE.Entitlement.List`, `IdLE.Entitlement.Revoke`, `IdLE.Entitlement.Grant`

## Synopsis

Removes all non-kept entitlements and GUARANTEES explicit Keep entries are present (grants if missing).

## Description

*** REMOVE + ENSURE step. This step REMOVES non-kept entitlements AND GRANTS missing Keep entries. ***

Use this step when you want to:

1. Strip all entitlements of a given kind (e.g., all group memberships), AND

2. Guarantee that specific entitlements from With.Keep are present afterwards — even if they were
   not present before the step ran (they will be granted).

Use IdLE.Step.PruneEntitlements instead when you only need removal and do NOT need any grants
(e.g., cleanup-only without a mandatory retention group).

Key behavioral difference vs PruneEntitlements: this EnsureKeep variant only accepts explicit
With.Keep entries. Wildcard retention via With.KeepPattern is not supported because patterns
cannot be granted reliably. If you need to protect entitlements via wildcard matches without
granting them, run IdLE.Step.PruneEntitlements or another cleanup step before this EnsureKeep
step.

With.Keep entries -> kept (NOT removed) AND ensured (GRANTED if currently missing). After this
step completes, every identity referenced by With.Keep is guaranteed to hold that entitlement —
regardless of whether it was already present.

With.Keep is optional. If omitted, all current entitlements of the given Kind are removed and no
grants are made (equivalent to PruneEntitlements with no keep-set). The AD provider always
excludes the primary group from the remove-set.

Provider contract:

- Must advertise the IdLE.Entitlement.Prune capability (explicit opt-in)

- Must implement ListEntitlements(identityKey)

- Must implement RevokeEntitlement(identityKey, entitlement)

- Must implement GrantEntitlement(identityKey, entitlement)  ← required; absent in PruneEntitlements

Non-removable entitlements (e.g., AD primary group / Domain Users) are handled safely: if a revoke
operation fails, the step emits a structured warning event, records the item as Skipped, and
continues. The workflow is not failed.

Authentication is handled by the engine (With.AuthSessionName, With.AuthSessionOptions).

## Inputs (With.*)

Validated at plan time against the step's ``WithSchema`` (see [Step metadata contract](../../extend/steps.md#step-metadata-contract)).

| Key | Type | Required | Default | Notes |
| --- | --- | --- | --- | --- |
| `IdentityKey` | String | Yes |  |  |
| `Kind` | String | Yes |  |  |
| `Keep` | Array | No |  | Items: `DisplayName`, `Id` (required), `Kind` |
| `AuthSessionName` | String | No | broker default session | Auth session routing key for the AuthSessionBroker. |
| `AuthSessionOptions` | Hashtable | No |  | Data-only options passed to the AuthSessionBroker. |
| `Provider` | String | No | `Identity` | Provider alias in `Providers`. |

## Example

### Example 1

```powershell
# Leaver workflow: remove ALL group memberships AND guarantee the identity is in the leaver-retention
# group. The retention group is both protected from removal AND granted if it is currently missing.
# This is the most common leaver scenario — contrast with PruneEntitlements (remove-only, no grants).
#
# After this step:
#   - CN=LEAVER-RETAIN,...  is present  (kept + granted if it was missing)
#   - All other groups      are removed
@{
    Name      = 'Prune groups and ensure leaver-retention group (leaver)'
    Type      = 'IdLE.Step.PruneEntitlementsEnsureKeep'
    Condition = @{ Equals = @{ Path = 'Request.Intent.PruneGroups'; Value = $true } }
    With      = @{
        IdentityKey     = '{{Request.Identity.SamAccountName}}'
        Provider        = 'Identity'
        Kind            = 'Group'
        # KEPT + GRANTED if missing: after the step, the identity is guaranteed to be a member.
        Keep            = @(
            @{ Kind = 'Group'; Id = 'CN=LEAVER-RETAIN,OU=Groups,DC=contoso,DC=com' }
        )
        # Pattern-based retention is not supported by EnsureKeep. Use IdLE.Step.PruneEntitlements
        # earlier in the workflow if you must preserve wildcard-matched entitlements without grants.
        AuthSessionName = 'Directory'
    }
}
```

### Example 2

```powershell
# Mover workflow: strip all license assignments except a baseline license, and guarantee the
# identity holds the baseline even if it was somehow removed before this step runs.
@{
    Name      = 'Reset license assignments to baseline (mover)'
    Type      = 'IdLE.Step.PruneEntitlementsEnsureKeep'
    Condition = @{ Equals = @{ Path = 'Request.Intent.ResetLicenses'; Value = $true } }
    With      = @{
        IdentityKey     = '{{Request.Identity.UserPrincipalName}}'
        Provider        = 'Licensing'
        Kind            = 'License'
        # This license is KEPT and GRANTED if missing — always present after this step.
        Keep            = @(
            @{ Kind = 'License'; Id = 'BASELINE-E1' }
        )
        AuthSessionName = 'Licensing'
    }
}
```

## See Also

- [Capabilities Reference](../capabilities.md) - Details on required capabilities
- [Providers](../providers.md) - Available provider implementations

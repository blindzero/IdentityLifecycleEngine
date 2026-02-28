# IdLE.Step.PruneEntitlementsEnsureKeep

> Generated file. Do not edit by hand.
> Source: tools/Generate-IdleStepReference.ps1

## Summary

- **Step Type**: `IdLE.Step.PruneEntitlementsEnsureKeep`
- **Module**: `IdLE.Steps.Common`
- **Implementation**: `Invoke-IdleStepPruneEntitlementsEnsureKeep`
- **Idempotent**: `Unknown`

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

Key behavioral difference vs PruneEntitlements — how With.Keep and With.KeepPattern behave:

  With.Keep entries    → kept (NOT removed) AND ensured (GRANTED if currently missing)
  With.KeepPattern     → kept (NOT removed) but NOT ensured (patterns cannot be granted)

This means after this step completes, every identity referenced by a With.Keep entry is
guaranteed to hold that entitlement — regardless of whether it was already present or not.
Pattern-matched entitlements that were already present are kept, but the step does not
search for or grant patterns that are not yet present.

At least one of With.Keep or With.KeepPattern must be supplied.

Provider contract:

- Must advertise the IdLE.Entitlement.Prune capability (explicit opt-in)

- Must implement ListEntitlements(identityKey)

- Must implement RevokeEntitlement(identityKey, entitlement)

- Must implement GrantEntitlement(identityKey, entitlement)  ← required; absent in PruneEntitlements

Non-removable entitlements (e.g., AD primary group / Domain Users) are handled safely: if a revoke
operation fails, the step emits a structured warning event, records the item as Skipped, and
continues. The workflow is not failed.

Authentication:

- If With.AuthSessionName is present, the step acquires an auth session via
  Context.AcquireAuthSession(Name, Options) and passes it to provider methods.

- With.AuthSessionOptions (optional, hashtable) is passed to the broker for session selection
  (e.g., @\{ Role = 'Tier0' \}). ScriptBlocks in AuthSessionOptions are rejected.

### With.* Parameters

| Key                  | Required | Type         | Description |
| -------------------- | -------- | ------------ | ----------- |
| IdentityKey          | Yes      | string       | Unique identity reference (e.g. sAMAccountName, UPN, or objectId). |
| Kind                 | Yes      | string       | Entitlement kind to prune (provider-defined, e.g. Group, Role, License). |
| Keep                 | No*      | array        | Explicit entitlement objects to retain AND ensure are present. Each entry must have an Id property; Kind and DisplayName are optional. **These entries are GRANTED if missing after the prune.** *At least one of Keep or KeepPattern is required. |
| KeepPattern          | No*      | string array | Wildcard strings (PowerShell -like semantics). Current entitlements whose Id matches any pattern are kept but NOT ensured — patterns cannot be granted. *At least one of Keep or KeepPattern is required. |
| Provider             | No       | string       | Provider alias from Context.Providers (default: Identity). |
| AuthSessionName      | No       | string       | Name of the auth session to acquire via Context.AcquireAuthSession. |
| AuthSessionOptions   | No       | hashtable    | Options passed to AcquireAuthSession for session selection (e.g. role-scoped sessions). |

## Inputs (With.*)

The required input keys could not be detected automatically.
Please refer to the step description and examples for usage details.

## Example

### Example 1

```powershell
# Leaver workflow: remove ALL group memberships AND guarantee the identity is in the leaver-retention
# group. The retention group is both protected from removal AND granted if it is currently missing.
# This is the most common leaver scenario — contrast with PruneEntitlements (remove-only, no grants).
#
# After this step:
#   - CN=LEAVER-RETAIN,...  is present  (kept + granted if it was missing)
#   - CN=LEAVER-*,...       are present  (kept if they were already there; not granted if missing)
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
        # KEPT but NOT granted: already-present LEAVER-* groups are preserved; absent ones are not added.
        KeepPattern     = @('CN=LEAVER-*,OU=Groups,DC=contoso,DC=com')
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

- [Capabilities Reference](../capabilities.md) - Overview of IdLE capabilities
- [Providers](../providers.md) - Available provider implementations

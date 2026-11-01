# IdLE.Step.PruneEntitlements

> Generated file. Do not edit by hand.
> Source: tools/Generate-IdleStepReference.ps1

## Summary

- **Step Type**: `IdLE.Step.PruneEntitlements`
- **Module**: `IdLE.Steps.Common`
- **Implementation**: `Invoke-IdleStepPruneEntitlements`
- **Idempotent**: `Unknown`
- **Required Capabilities**: `IdLE.Entitlement.Prune`, `IdLE.Entitlement.List`, `IdLE.Entitlement.Revoke`

## Synopsis

Removes all non-kept entitlements of a given kind from an identity. Remove-only — does not grant anything.

## Description

*** REMOVE-ONLY step. This step NEVER grants entitlements. ***

Use this step when you want to strip an identity of all entitlements of a given kind (e.g., all group
memberships) and you do NOT need to guarantee that any specific entitlement is actually present
afterwards. The step reads the current entitlements once, computes the remove-set (all entitlements
that are NOT in the keep-set), and revokes each one individually.

Use IdLE.Step.PruneEntitlementsEnsureKeep instead when you also need to guarantee that one or more
explicit Keep entries are present after the prune (e.g., a leaver-retention group must be granted
if it is missing).

With.Kind is the prune scope: only current entitlements of this Kind are considered for removal.
The provider rejects a Kind it does not support (e.g., 'AdministrativeUnit' on AD) before anything
is removed. To prune several Kinds, use one step per Kind.

How the keep-set is built:

- With.Keep      — explicit entitlement references (kept AND matched case-insensitively by Id).
                   Entries inherit With.Kind; an entry may repeat Kind, but a different Kind fails
                   the step before anything is removed.

- With.KeepPattern — wildcard strings (-like semantics); any current entitlement whose Id matches
                    is kept. Patterns are NEVER granted, only protected from removal.

If neither With.Keep nor With.KeepPattern is supplied, ALL current entitlements of the given Kind
are removed (no keep-set). On the AD provider the primary group is always excluded by ListEntitlements
and is never placed in the remove-set.

Provider contract:

- Must advertise the IdLE.Entitlement.Prune capability (explicit opt-in)

- Must implement ListEntitlements(identityKey)

- Must implement RevokeEntitlement(identityKey, entitlement)

- GrantEntitlement is NOT called by this step.

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
| `KeepPattern` | Array | No |  | Items: String |
| `AuthSessionName` | String | No | broker default session | Auth session routing key for the AuthSessionBroker. |
| `AuthSessionOptions` | Hashtable | No |  | Data-only options passed to the AuthSessionBroker. |
| `Provider` | String | No | `Identity` | Provider alias in `Providers`. |

## Example

### Example 1

```powershell
# Mover workflow: strip all role assignments except those matching a wildcard pattern.
# REMOVE-ONLY — no groups are granted. If you also need to ensure a specific role is present,
# use IdLE.Step.PruneEntitlementsEnsureKeep instead.
@{
    Name      = 'Strip role assignments (mover)'
    Type      = 'IdLE.Step.PruneEntitlements'
    Condition = @{ Equals = @{ Path = 'Request.Intent.StripRoles'; Value = $true } }
    With      = @{
        IdentityKey     = '{{Request.Identity.UserPrincipalName}}'
        Provider        = 'Identity'
        Kind            = 'Role'
        # Keep any role whose Id matches this pattern — everything else is removed.
        # No entitlements are granted; this is a cleanup-only operation.
        KeepPattern     = @('ROLE-READONLY-*')
        AuthSessionName = 'Directory'
    }
}
```

### Example 2

```powershell
# Leaver workflow: remove all group memberships except a static keep-list.
# The identity will NOT be added to any group — only existing memberships outside the keep-list
# are removed. For a guaranteed leaver-retention group use PruneEntitlementsEnsureKeep.
@{
    Name      = 'Remove group memberships (leaver, remove-only)'
    Type      = 'IdLE.Step.PruneEntitlements'
    Condition = @{ Equals = @{ Path = 'Request.Intent.PruneGroups'; Value = $true } }
    With      = @{
        IdentityKey     = '{{Request.Identity.SamAccountName}}'
        Provider        = 'Identity'
        Kind            = 'Group'
        Keep            = @(
            # Kept if currently a member — but NOT granted if missing.
            @{ Id = 'CN=All-Users,OU=Groups,DC=contoso,DC=com' }
        )
        KeepPattern     = @('CN=LEAVER-*,OU=Groups,DC=contoso,DC=com')
        AuthSessionName = 'Directory'
    }
}
```

## See Also

- [Capabilities Reference](../capabilities.md) - Details on required capabilities
- [Providers](../providers.md) - Available provider implementations

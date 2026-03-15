# IdLE.Step.PruneEntitlements

> Generated file. Do not edit by hand.
> Source: tools/Generate-IdleStepReference.ps1

## Summary

- **Step Type**: `IdLE.Step.PruneEntitlements`
- **Module**: `IdLE.Steps.Common`
- **Implementation**: `Invoke-IdleStepPruneEntitlements`
- **Idempotent**: `Unknown`

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

How the keep-set is built:

- With.Keep      — explicit entitlement references (kept AND matched case-insensitively by Id)

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
| Keep                 | No       | array        | Explicit entitlement objects to retain (kept, never removed). Each entry must have an Id property; Kind is optional. These entries are NOT granted — use PruneEntitlementsEnsureKeep for that. |
| KeepPattern          | No       | string array | Wildcard strings (PowerShell -like semantics). Current entitlements whose Id matches any pattern are kept. Patterns are NEVER granted. |
| Provider             | No       | string       | Provider alias from Context.Providers (default: Identity). |
| AuthSessionName      | No       | string       | Name of the auth session to acquire via Context.AcquireAuthSession. |
| AuthSessionOptions   | No       | hashtable    | Options passed to AcquireAuthSession for session selection (e.g. role-scoped sessions). |

## Inputs (With.*)

The following keys are required in the step's ``With`` configuration:

| Key | Required | Description |
| --- | --- | --- |
| `IdentityKey` | Yes | Unique identifier for the identity |
| `Kind` | Yes | See step description for details |

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
            @{ Kind = 'Group'; Id = 'CN=All-Users,OU=Groups,DC=contoso,DC=com' }
        )
        KeepPattern     = @('CN=LEAVER-*,OU=Groups,DC=contoso,DC=com')
        AuthSessionName = 'Directory'
    }
}
```

## See Also

- [Capabilities Reference](../capabilities.md) - Overview of IdLE capabilities
- [Providers](../providers.md) - Available provider implementations

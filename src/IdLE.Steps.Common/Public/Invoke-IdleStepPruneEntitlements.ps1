function Invoke-IdleStepPruneEntitlements {
    <#
    .SYNOPSIS
    Removes all non-kept entitlements of a given kind from an identity. Remove-only — does not grant anything.

    .DESCRIPTION
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

    Authentication is handled by the engine (With.AuthSessionName, With.AuthSessionOptions).

    .PARAMETER Context
    Execution context created by IdLE.Core.

    .PARAMETER With
    Validated With hashtable (see the step metadata catalog).

    .PARAMETER Provider
    Provider handle created by the engine (see docs/extend/steps.md).

    .PARAMETER Step
    Step metadata (Name, Type); the name is used for events.

    .EXAMPLE
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

    .EXAMPLE
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

    .OUTPUTS
    System.Collections.Hashtable (Changed, Data.Skipped)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Context,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable] $With,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Provider,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Step
    )

    return Invoke-IdlePruneEntitlementsOperation -Context $Context -With $With -Provider $Provider -StepName ([string]$Step.Name)
}

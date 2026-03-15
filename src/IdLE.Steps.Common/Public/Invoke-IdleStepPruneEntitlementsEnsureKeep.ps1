function Invoke-IdleStepPruneEntitlementsEnsureKeep {
    <#
    .SYNOPSIS
    Removes all non-kept entitlements and GUARANTEES explicit Keep entries are present (grants if missing).

    .DESCRIPTION
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

    Authentication:
    - If With.AuthSessionName is present, the step acquires an auth session via
      Context.AcquireAuthSession(Name, Options) and passes it to provider methods.
    - With.AuthSessionOptions (optional, hashtable) is passed to the broker for session selection
      (e.g., @{ Role = 'Tier0' }). ScriptBlocks in AuthSessionOptions are rejected.

    ### With.* Parameters

    | Key                  | Required | Type         | Description |
    | -------------------- | -------- | ------------ | ----------- |
    | IdentityKey          | Yes      | string       | Unique identity reference (e.g. sAMAccountName, UPN, or objectId). |
    | Kind                 | Yes      | string       | Entitlement kind to prune (provider-defined, e.g. Group, Role, License). |
    | Keep                 | No       | array        | Explicit entitlement objects to retain AND ensure are present. Each entry must have an Id property; Kind is optional. **These entries are GRANTED if missing after the prune.** If omitted, all entitlements of the given Kind are removed and no grants are made. |
    | Provider             | No       | string       | Provider alias from Context.Providers (default: Identity). |
    | AuthSessionName      | No       | string       | Name of the auth session to acquire via Context.AcquireAuthSession. |
    | AuthSessionOptions   | No       | hashtable    | Options passed to AcquireAuthSession for session selection (e.g. role-scoped sessions). |

    .PARAMETER Context
    Execution context created by IdLE.Core.

    .PARAMETER Step
    Normalized step object from the plan. Must contain a 'With' hashtable.

    .EXAMPLE
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

    .EXAMPLE
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

    .OUTPUTS
    PSCustomObject (PSTypeName: IdLE.StepResult)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Context,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Step
    )

    if ($null -eq $Step.With -or -not ($Step.With -is [hashtable])) {
        throw "PruneEntitlementsEnsureKeep requires 'With' to be a hashtable."
    }

    $sourceWith = $Step.With

    if ($sourceWith.ContainsKey('KeepPattern')) {
        throw "PruneEntitlementsEnsureKeep does not support With.KeepPattern. Use With.Keep for explicit entitlements to retain and ensure."
    }

    # Inject EnsureKeepEntitlements = $true into With, then delegate to Invoke-IdleStepPruneEntitlements.
    # This ensures the ensure-grant phase always runs for this step type.
    $ensureWith = [hashtable]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($key in $sourceWith.Keys) {
        $ensureWith[$key] = $sourceWith[$key]
    }
    $ensureWith['EnsureKeepEntitlements'] = $true

    # Shallow clone the step with the updated With
    $ensureStep = [pscustomobject]@{
        Name = [string]$Step.Name
        Type = [string]$Step.Type
        With = $ensureWith
    }
    if ($Step.PSObject.Properties.Name -contains 'Condition') {
        $ensureStep | Add-Member -MemberType NoteProperty -Name Condition -Value $Step.Condition
    }

    return Invoke-IdleStepPruneEntitlements -Context $Context -Step $ensureStep
}

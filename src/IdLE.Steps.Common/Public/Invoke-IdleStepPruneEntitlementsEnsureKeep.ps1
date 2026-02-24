function Invoke-IdleStepPruneEntitlementsEnsureKeep {
    <#
    .SYNOPSIS
    Converges an identity's entitlements by removing all non-kept entitlements and ensuring kept ones are present.

    .DESCRIPTION
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
      session selection (e.g., @{ Role = 'Tier0' }).
    - ScriptBlocks in AuthSessionOptions are rejected (security boundary).

    .PARAMETER Context
    Execution context created by IdLE.Core.

    .PARAMETER Step
    Normalized step object from the plan. Must contain a 'With' hashtable.

    .EXAMPLE
    Invoke-IdleStepPruneEntitlementsEnsureKeep -Context $context -Step [pscustomobject]@{
        Name = 'Prune group memberships and ensure leaver group (leaver)'
        Type = 'IdLE.Step.PruneEntitlementsEnsureKeep'
        With = @{
            IdentityKey = 'jsmith'
            Provider    = 'Identity'
            Kind        = 'Group'
            Keep        = @(
                @{ Kind = 'Group'; Id = 'CN=LEAVER-RETAIN,OU=Groups,DC=contoso,DC=com' }
            )
            KeepPattern = @('CN=LEAVER-*,OU=Groups,DC=contoso,DC=com')
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

    # Inject EnsureKeepEntitlements = $true into With, then delegate to Invoke-IdleStepPruneEntitlements.
    # This ensures the ensure-grant phase always runs for this step type.
    $ensureWith = [hashtable]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($key in $Step.With.Keys) {
        $ensureWith[$key] = $Step.With[$key]
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

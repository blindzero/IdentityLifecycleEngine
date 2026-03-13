function Get-IdleStepMetadataCatalog {
    <#
    .SYNOPSIS
    Returns metadata for common built-in IdLE step types.

    .DESCRIPTION
    This function provides a metadata catalog mapping Step.Type to metadata objects.
    Each metadata object contains RequiredCapabilities (array of capability identifiers).

    The metadata is used during plan building to derive required provider capabilities
    for each step, removing the need to declare RequiresCapabilities in workflow definitions.

    .OUTPUTS
    Hashtable (case-insensitive) mapping Step.Type (string) to metadata (hashtable).

    .EXAMPLE
    $metadata = Get-IdleStepMetadataCatalog
    $metadata['IdLE.Step.DisableIdentity'].RequiredCapabilities
    # Returns: @('IdLE.Identity.Disable')
    #>
    [CmdletBinding()]
    param()

    $catalog = [hashtable]::new([System.StringComparer]::OrdinalIgnoreCase)

    # IdLE.Step.EmitEvent - no provider capabilities required (writes to event sink only)
    $catalog['IdLE.Step.EmitEvent'] = @{
        RequiredCapabilities = @()
    }

    # IdLE.Step.CreateIdentity - requires identity creation capability
    $catalog['IdLE.Step.CreateIdentity'] = @{
        RequiredCapabilities = @('IdLE.Identity.Create')
    }

    # IdLE.Step.DisableIdentity - requires identity disable capability
    $catalog['IdLE.Step.DisableIdentity'] = @{
        RequiredCapabilities = @('IdLE.Identity.Disable')
    }

    # IdLE.Step.EnableIdentity - requires identity enable capability
    $catalog['IdLE.Step.EnableIdentity'] = @{
        RequiredCapabilities = @('IdLE.Identity.Enable')
    }

    # IdLE.Step.DeleteIdentity - requires identity delete capability
    $catalog['IdLE.Step.DeleteIdentity'] = @{
        RequiredCapabilities = @('IdLE.Identity.Delete')
    }

    # IdLE.Step.MoveIdentity - requires identity move capability
    $catalog['IdLE.Step.MoveIdentity'] = @{
        RequiredCapabilities = @('IdLE.Identity.Move')
    }

    # IdLE.Step.EnsureAttributes - requires identity attribute ensure capability
    $catalog['IdLE.Step.EnsureAttributes'] = @{
        RequiredCapabilities = @('IdLE.Identity.Attribute.Ensure')
    }

    # IdLE.Step.EnsureEntitlement - requires entitlement list and grant/revoke capabilities
    $catalog['IdLE.Step.EnsureEntitlement'] = @{
        RequiredCapabilities = @('IdLE.Entitlement.List', 'IdLE.Entitlement.Grant', 'IdLE.Entitlement.Revoke')
    }

    # IdLE.Step.RevokeIdentitySessions - requires identity session revocation capability
    $catalog['IdLE.Step.RevokeIdentitySessions'] = @{
        RequiredCapabilities = @('IdLE.Identity.RevokeSessions')
    }

    # IdLE.Step.PruneEntitlements - remove-only: requires explicit prune opt-in capability plus list/revoke
    $catalog['IdLE.Step.PruneEntitlements'] = @{
        RequiredCapabilities = @('IdLE.Entitlement.Prune', 'IdLE.Entitlement.List', 'IdLE.Entitlement.Revoke')
        AllowedWithKeys      = @('IdentityKey', 'Kind', 'Provider', 'Keep', 'KeepPattern', 'AuthSessionName', 'AuthSessionOptions')
    }

    # IdLE.Step.PruneEntitlementsEnsureKeep - remove + ensure keep present: requires prune + list/revoke/grant
    # KeepPattern is NOT in AllowedWithKeys because patterns cannot be "ensured" (granted); plan-time
    # validation rejects any With key that is not in this list.
    $catalog['IdLE.Step.PruneEntitlementsEnsureKeep'] = @{
        RequiredCapabilities = @('IdLE.Entitlement.Prune', 'IdLE.Entitlement.List', 'IdLE.Entitlement.Revoke', 'IdLE.Entitlement.Grant')
        AllowedWithKeys      = @('IdentityKey', 'Kind', 'Provider', 'Keep', 'AuthSessionName', 'AuthSessionOptions')
    }

    return $catalog
}

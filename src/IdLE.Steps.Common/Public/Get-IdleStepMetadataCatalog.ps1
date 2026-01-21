function Get-IdleStepMetadataCatalog {
    <#
    .SYNOPSIS
    Returns metadata for built-in IdLE step types.

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
    # Returns: @('IdLE.Identity.Disable', 'IdLE.Identity.Read')
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

    # IdLE.Step.EnsureAttribute - requires identity attribute ensure capability
    $catalog['IdLE.Step.EnsureAttribute'] = @{
        RequiredCapabilities = @('IdLE.Identity.Attribute.Ensure')
    }

    # IdLE.Step.EnsureEntitlement - requires entitlement list and grant/revoke capabilities
    $catalog['IdLE.Step.EnsureEntitlement'] = @{
        RequiredCapabilities = @('IdLE.Entitlement.List', 'IdLE.Entitlement.Grant', 'IdLE.Entitlement.Revoke')
    }

    return $catalog
}

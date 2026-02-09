function Get-IdleStepMetadataCatalog {
    <#
    .SYNOPSIS
    Returns metadata for mailbox step types.

    .DESCRIPTION
    This function provides a metadata catalog mapping Step.Type to metadata objects.
    Each metadata object contains RequiredCapabilities (array of capability identifiers).

    The metadata is used during plan building to derive required provider capabilities
    for each step, removing the need to declare RequiresCapabilities in workflow definitions.

    This catalog declares mailbox-specific step types that work with any provider
    implementing the mailbox provider contract.

    .OUTPUTS
    Hashtable (case-insensitive) mapping Step.Type (string) to metadata (hashtable).

    .EXAMPLE
    $metadata = Get-IdleStepMetadataCatalog
    $metadata['IdLE.Step.Mailbox.GetInfo'].RequiredCapabilities
    # Returns: @('IdLE.Mailbox.Info.Read')
    #>
    [CmdletBinding()]
    param()

    $catalog = [hashtable]::new([System.StringComparer]::OrdinalIgnoreCase)

    # IdLE.Step.Mailbox.GetInfo - read mailbox details
    $catalog['IdLE.Step.Mailbox.GetInfo'] = @{
        RequiredCapabilities = @('IdLE.Mailbox.Info.Read')
    }

    # IdLE.Step.Mailbox.EnsureType - idempotent mailbox type conversion
    $catalog['IdLE.Step.Mailbox.EnsureType'] = @{
        RequiredCapabilities = @('IdLE.Mailbox.Info.Read', 'IdLE.Mailbox.Type.Ensure')
    }

    # IdLE.Step.Mailbox.EnsureOutOfOffice - idempotent Out of Office configuration
    $catalog['IdLE.Step.Mailbox.EnsureOutOfOffice'] = @{
        RequiredCapabilities = @('IdLE.Mailbox.Info.Read', 'IdLE.Mailbox.OutOfOffice.Ensure')
    }

    return $catalog
}

function Get-IdleStepMetadataCatalog {
    <#
    .SYNOPSIS
    Returns metadata for DirectorySync step types.

    .DESCRIPTION
    This function provides a metadata catalog mapping Step.Type to metadata objects
    for directory sync step types owned by this step pack.

    Each metadata object contains RequiredCapabilities (array of capability identifiers).

    The metadata is used during plan building to derive required provider capabilities
    for each step, removing the need to declare RequiresCapabilities in workflow definitions.

    .OUTPUTS
    Hashtable (case-insensitive) mapping Step.Type (string) to metadata (hashtable).

    .EXAMPLE
    $metadata = Get-IdleStepMetadataCatalog
    $metadata['IdLE.Step.TriggerDirectorySync'].RequiredCapabilities
    # Returns: @('IdLE.DirectorySync.Trigger', 'IdLE.DirectorySync.Status')
    #>
    [CmdletBinding()]
    param()

    $catalog = [hashtable]::new([System.StringComparer]::OrdinalIgnoreCase)

    # IdLE.Step.TriggerDirectorySync - requires trigger and status capabilities
    # Note: Even when With.Wait = $false, we advertise Status capability to keep planning deterministic
    $catalog['IdLE.Step.TriggerDirectorySync'] = @{
        RequiredCapabilities = @('IdLE.DirectorySync.Trigger', 'IdLE.DirectorySync.Status')
    }

    return $catalog
}

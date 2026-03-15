function Get-IdleStepMetadataCatalog {
    <#
    .SYNOPSIS
    Returns metadata for common built-in IdLE step types.

    .DESCRIPTION
    This function loads and returns the step metadata catalog for common built-in IdLE step types.
    The catalog is defined in StepMetadataCatalog.psd1 (data-only, no ScriptBlocks).

    Each metadata object contains:
      RequiredCapabilities - capability identifiers the step requires from providers
      WithSchema           - the With key contract used for plan-time validation

    The metadata is used during plan building to derive required provider capabilities
    for each step and to validate With parameters.

    .OUTPUTS
    Hashtable (case-insensitive) mapping Step.Type (string) to metadata (hashtable).

    .EXAMPLE
    $metadata = Get-IdleStepMetadataCatalog
    $metadata['IdLE.Step.DisableIdentity'].RequiredCapabilities
    # Returns: @('IdLE.Identity.Disable')
    #>
    [CmdletBinding()]
    param()

    $catalogPath = Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'StepMetadataCatalog.psd1'
    $rawData = Import-PowerShellDataFile -Path $catalogPath

    $catalog = [hashtable]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($key in $rawData.Keys) {
        $catalog[$key] = $rawData[$key]
    }

    return $catalog
}

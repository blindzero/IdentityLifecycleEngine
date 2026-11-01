function Get-IdleStepStateSchema {
    <#
    .SYNOPSIS
    Returns the effective root schema for the State a step publishes.

    .DESCRIPTION
    Wraps StateSchema.Keys into a Hashtable key schema (a data-only copy), or returns $null if the
    step metadata declares no StateSchema (the step publishes no State).

    .PARAMETER Metadata
    Step metadata entry (validated by Assert-IdleStepMetadataContract).

    .OUTPUTS
    System.Collections.Hashtable (key schema with Type = 'Hashtable') or $null.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable] $Metadata
    )

    if (-not $Metadata.ContainsKey('StateSchema')) {
        return $null
    }

    $stateSchema = $Metadata['StateSchema']
    return @{
        Type                = 'Hashtable'
        Keys                = Copy-IdleDataObject -Value $stateSchema['Keys']
        AllowAdditionalKeys = ($stateSchema.ContainsKey('AllowAdditionalKeys') -and $stateSchema['AllowAdditionalKeys'] -eq $true)
    }
}

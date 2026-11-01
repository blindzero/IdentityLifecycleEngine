function Get-IdleStepWithSchema {
    <#
    .SYNOPSIS
    Returns the effective root schema for a step's With hashtable.

    .DESCRIPTION
    Wraps WithSchema.Keys into a Hashtable key schema and adds the engine-provided common keys
    (Provider, AuthSessionName, AuthSessionOptions) when the step metadata declares a Provider.

    .PARAMETER Metadata
    Step metadata entry (validated by Assert-IdleStepMetadataContract).

    .OUTPUTS
    System.Collections.Hashtable (key schema with Type = 'Hashtable').
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable] $Metadata
    )

    $withSchema = $Metadata['WithSchema']

    $keys = [hashtable]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($key in $withSchema['Keys'].PSBase.Keys) {
        $keys[[string]$key] = $withSchema['Keys'][$key]
    }

    if ($Metadata.ContainsKey('Provider')) {
        $keys['Provider'] = @{ Type = 'String'; Default = [string]$Metadata['Provider']['DefaultAlias'] }
        $keys['AuthSessionName'] = @{ Type = 'String' }
        $keys['AuthSessionOptions'] = @{ Type = 'Hashtable' }
    }

    return @{
        Type                = 'Hashtable'
        Keys                = $keys
        AllowAdditionalKeys = ($withSchema.ContainsKey('AllowAdditionalKeys') -and $withSchema['AllowAdditionalKeys'] -eq $true)
    }
}

function ConvertTo-IdleStepWith {
    <#
    .SYNOPSIS
    Validates a step's With against its metadata and returns the effective With.

    .DESCRIPTION
    Plan-time step input contract (see docs/extend/steps.md):
    - With is validated against WithSchema (types, required keys, allowed values, nested keys).
    - Defaults are applied, including Provider = Provider.DefaultAlias for steps that declare a Provider.
    - Common keys (Provider, AuthSessionName, AuthSessionOptions) are only accepted for steps that declare a Provider.
    - Provider.AuthSessionNameFromAlias: AuthSessionName defaults to the resolved provider alias.

    .PARAMETER Metadata
    Step metadata entry.

    .PARAMETER With
    With hashtable from the workflow (templates already resolved).

    .PARAMETER StepName
    Step name (error messages).

    .PARAMETER StepType
    Step type (error messages).

    .OUTPUTS
    System.Collections.Hashtable
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable] $Metadata,

        [Parameter()]
        [AllowNull()]
        [object] $With,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $StepName,

        [Parameter(Mandatory)]
        [string] $StepType
    )

    if ($null -eq $With) { $With = @{} }

    $effective = ConvertTo-IdleSchemaValue `
        -Schema (Get-IdleStepWithSchema -Metadata $Metadata) `
        -Value $With `
        -Path 'With' `
        -ErrorPrefix ("Step '{0}' (type '{1}'):" -f $StepName, $StepType) `
        -ExcludedKeys @('Provider', 'AuthSessionName', 'AuthSessionOptions')

    # Steps whose auth sessions are named after the provider alias (e.g. 'ExchangeOnline').
    if ($Metadata.ContainsKey('Provider') -and $Metadata['Provider']['AuthSessionNameFromAlias'] -eq $true -and -not $effective.ContainsKey('AuthSessionName')) {
        $effective['AuthSessionName'] = [string]$effective['Provider']
    }

    return $effective
}

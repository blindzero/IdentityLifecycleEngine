function Invoke-IdleStepCreateIdentity {
    <#
    .SYNOPSIS
    Creates a new identity in the target system.

    .DESCRIPTION
    This is a provider-agnostic step. The engine passes the provider resolved from With.Provider (default 'Identity') as -Provider.
    The provider implements CreateIdentity(identityKey, attributes)
    and returns an object with properties 'IdentityKey' and 'Changed'.

    The step is idempotent by design: if the identity already exists, the provider
    should return Changed = $false without creating a duplicate.

    Authentication is handled by the engine: With.AuthSessionName and With.AuthSessionOptions select the
    auth session passed to provider methods that declare an AuthSession parameter.

    .PARAMETER With
    Validated With hashtable (see the step metadata catalog):
    - IdentityKey (required): the identity identifier
    - Attributes (required): hashtable of attributes to set on the new identity

    .PARAMETER Provider
    Provider handle created by the engine (see docs/extend/steps.md).

    .OUTPUTS
    System.Collections.Hashtable (Changed)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable] $With,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Provider
    )

    $result = $Provider.Invoke('CreateIdentity', @($With.IdentityKey, $With.Attributes))

    $changed = $null -ne $result -and ($result.PSObject.Properties.Name -contains 'Changed') -and [bool]$result.Changed
    return @{ Changed = $changed }
}

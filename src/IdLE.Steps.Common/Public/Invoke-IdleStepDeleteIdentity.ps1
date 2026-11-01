function Invoke-IdleStepDeleteIdentity {
    <#
    .SYNOPSIS
    Deletes an identity from the target system.

    .DESCRIPTION
    This is a provider-agnostic step. The engine passes the provider resolved from With.Provider (default 'Identity') as -Provider.
    The provider implements DeleteIdentity(identityKey)
    and returns an object with properties 'IdentityKey' and 'Changed'.

    The step is idempotent by design: if the identity is already deleted, the provider
    should return Changed = $false.

    IMPORTANT: This step requires the provider to advertise the IdLE.Identity.Delete
    capability, which is typically opt-in for safety. The provider must be configured
    to allow deletion (e.g., AllowDelete = $true for AD provider).

    Authentication is handled by the engine: With.AuthSessionName and With.AuthSessionOptions select the
    auth session passed to provider methods that declare an AuthSession parameter.

    .PARAMETER With
    Validated With hashtable (see the step metadata catalog):
    - IdentityKey (required): the identity identifier

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

    $result = $Provider.Invoke('DeleteIdentity', @($With.IdentityKey))

    $changed = $null -ne $result -and ($result.PSObject.Properties.Name -contains 'Changed') -and [bool]$result.Changed
    return @{ Changed = $changed }
}

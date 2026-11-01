function Invoke-IdleStepRevokeIdentitySessions {
    <#
    .SYNOPSIS
    Revokes all active sign-in sessions for an identity in the target system.

    .DESCRIPTION
    This is a provider-agnostic step that revokes active sign-in sessions (refresh tokens)
    for a given identity. The engine passes the provider resolved from With.Provider (default 'Identity') as -Provider.
    The provider implements RevokeSessions(identityKey)
    and returns an object with properties 'IdentityKey' and 'Changed'.

    This step is typically used in Leaver workflows after disabling an identity to ensure
    that existing sessions are terminated immediately, rather than waiting for tokens to expire.

    The step does not modify the identity itself (e.g., does not disable the account).
    Use IdLE.Step.DisableIdentity separately if account disabling is also required.

    Authentication is handled by the engine: With.AuthSessionName and With.AuthSessionOptions select the
    auth session passed to provider methods that declare an AuthSession parameter.

    .PARAMETER With
    Validated With hashtable (see the step metadata catalog):
    - IdentityKey (required): the identity identifier

    .PARAMETER Provider
    Provider handle created by the engine (see docs/extend/steps.md).
    - AuthSessionName (optional): name for auth session acquisition
    - AuthSessionOptions (optional): routing options for auth session broker

    .OUTPUTS
    System.Collections.Hashtable (Changed)

    .EXAMPLE
    # In a workflow definition (PSD1):
    @{
        Name = 'Revoke Entra sessions'
        Type = 'IdLE.Step.RevokeIdentitySessions'
        With = @{
            Provider = 'Entra'
            IdentityKey = 'max.power@contoso.com'
            AuthSessionName = 'MicrosoftGraph'
            AuthSessionOptions = @{ Role = 'Admin' }
        }
    }

    .NOTES
    Requires provider capability: IdLE.Identity.RevokeSessions

    For Entra ID provider, this calls Microsoft Graph API:
    POST /users/{id}/revokeSignInSessions

    Required Graph permissions: User.RevokeSessions.All

    Note: Session revocation may not be instantaneous; a small propagation delay may occur
    depending on the identity provider and token lifetime policies.
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

    $result = $Provider.Invoke('RevokeSessions', @($With.IdentityKey))

    $changed = $null -ne $result -and ($result.PSObject.Properties.Name -contains 'Changed') -and [bool]$result.Changed
    return @{ Changed = $changed }
}

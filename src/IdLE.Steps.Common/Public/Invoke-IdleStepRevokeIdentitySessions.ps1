function Invoke-IdleStepRevokeIdentitySessions {
    <#
    .SYNOPSIS
    Revokes all active sign-in sessions for an identity in the target system.

    .DESCRIPTION
    This is a provider-agnostic step that revokes active sign-in sessions (refresh tokens)
    for a given identity. The host must supply a provider instance via
    Context.Providers[<ProviderAlias>] that implements RevokeSessions(identityKey)
    and returns an object with properties 'IdentityKey' and 'Changed'.

    This step is typically used in Leaver workflows after disabling an identity to ensure
    that existing sessions are terminated immediately, rather than waiting for tokens to expire.

    The step does not modify the identity itself (e.g., does not disable the account).
    Use IdLE.Step.DisableIdentity separately if account disabling is also required.

    Authentication:
    - If With.AuthSessionName is present, the step acquires an auth session via
      Context.AcquireAuthSession(Name, Options) and passes it to the provider method
      if the provider supports an AuthSession parameter.
    - With.AuthSessionOptions (optional, hashtable) is passed to the broker for
      session selection (e.g., @{ Role = 'Tier0' }).
    - ScriptBlocks in AuthSessionOptions are rejected (security boundary).

    .PARAMETER Context
    Execution context created by IdLE.Core.

    .PARAMETER Step
    Normalized step object from the plan. Must contain a 'With' hashtable with keys:
    - IdentityKey (required): the identity identifier
    - Provider (optional): provider alias, defaults to 'Identity'
    - AuthSessionName (optional): name for auth session acquisition
    - AuthSessionOptions (optional): routing options for auth session broker

    .OUTPUTS
    PSCustomObject (PSTypeName: IdLE.StepResult)

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
        [object] $Context,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Step
    )

    $with = $Step.With
    if ($null -eq $with -or -not ($with -is [hashtable])) {
        throw "RevokeIdentitySessions requires 'With' to be a hashtable."
    }

    if (-not $with.ContainsKey('IdentityKey')) {
        throw "RevokeIdentitySessions requires With.IdentityKey."
    }

    $providerAlias = if ($with.ContainsKey('Provider')) { [string]$with.Provider } else { 'Identity' }

    if (-not ($Context.PSObject.Properties.Name -contains 'Providers')) {
        throw "Context does not contain a Providers hashtable."
    }
    if ($null -eq $Context.Providers -or -not ($Context.Providers -is [hashtable])) {
        throw "Context.Providers must be a hashtable."
    }
    if (-not $Context.Providers.ContainsKey($providerAlias)) {
        throw "Provider '$providerAlias' was not supplied by the host."
    }

    $result = Invoke-IdleProviderMethod `
        -Context $Context `
        -With $with `
        -ProviderAlias $providerAlias `
        -MethodName 'RevokeSessions' `
        -MethodArguments @([string]$with.IdentityKey)

    $changed = $false
    if ($null -ne $result -and ($result.PSObject.Properties.Name -contains 'Changed')) {
        $changed = [bool]$result.Changed
    }

    return [pscustomobject]@{
        PSTypeName = 'IdLE.StepResult'
        Name       = [string]$Step.Name
        Type       = [string]$Step.Type
        Status     = 'Completed'
        Changed    = $changed
        Error      = $null
    }
}

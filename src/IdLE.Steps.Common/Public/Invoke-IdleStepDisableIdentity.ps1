function Invoke-IdleStepDisableIdentity {
    <#
    .SYNOPSIS
    Disables an identity in the target system.

    .DESCRIPTION
    This is a provider-agnostic step. The host must supply a provider instance via
    Context.Providers[<ProviderAlias>] that implements DisableIdentity(identityKey)
    and returns an object with properties 'IdentityKey' and 'Changed'.

    The step is idempotent by design: if the identity is already disabled, the provider
    should return Changed = $false.

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

    .OUTPUTS
    PSCustomObject (PSTypeName: IdLE.StepResult)
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
        throw "DisableIdentity requires 'With' to be a hashtable."
    }

    if (-not $with.ContainsKey('IdentityKey')) {
        throw "DisableIdentity requires With.IdentityKey."
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

    # Auth session acquisition (optional, data-only)
    $authSession = $null
    if ($with.ContainsKey('AuthSessionName')) {
        $sessionName = [string]$with.AuthSessionName
        $sessionOptions = if ($with.ContainsKey('AuthSessionOptions')) { $with.AuthSessionOptions } else { $null }

        if ($null -ne $sessionOptions -and -not ($sessionOptions -is [hashtable])) {
            throw "With.AuthSessionOptions must be a hashtable or null."
        }

        $authSession = $Context.AcquireAuthSession($sessionName, $sessionOptions)
    }

    $provider = $Context.Providers[$providerAlias]

    # Call provider with AuthSession if supported (backwards compatible fallback)
    $providerMethod = $provider.PSObject.Methods['DisableIdentity']
    if ($null -eq $providerMethod) {
        throw "Provider '$providerAlias' does not implement DisableIdentity method."
    }

    $supportsAuthSession = Test-IdleProviderMethodParameter -ProviderMethod $providerMethod -ParameterName 'AuthSession'

    # Call provider method with appropriate signature
    if ($supportsAuthSession -and $null -ne $authSession) {
        # Provider supports AuthSession and we have one - pass it
        $result = $provider.DisableIdentity([string]$with.IdentityKey, $authSession)
    }
    else {
        # Legacy signature (no AuthSession parameter) or no session acquired
        $result = $provider.DisableIdentity([string]$with.IdentityKey)
    }

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

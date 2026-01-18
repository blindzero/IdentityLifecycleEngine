function Invoke-IdleStepCreateIdentity {
    <#
    .SYNOPSIS
    Creates a new identity in the target system.

    .DESCRIPTION
    This is a provider-agnostic step. The host must supply a provider instance via
    Context.Providers[<ProviderAlias>] that implements CreateIdentity(identityKey, attributes)
    and returns an object with properties 'IdentityKey' and 'Changed'.

    The step is idempotent by design: if the identity already exists, the provider
    should return Changed = $false without creating a duplicate.

    .PARAMETER Context
    Execution context created by IdLE.Core.

    .PARAMETER Step
    Normalized step object from the plan. Must contain a 'With' hashtable with keys:
    - IdentityKey (required): the identity identifier
    - Attributes (required): hashtable of attributes to set on the new identity
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
        throw "CreateIdentity requires 'With' to be a hashtable."
    }

    foreach ($key in @('IdentityKey', 'Attributes')) {
        if (-not $with.ContainsKey($key)) {
            throw "CreateIdentity requires With.$key."
        }
    }

    if (-not ($with.Attributes -is [hashtable])) {
        throw "CreateIdentity requires With.Attributes to be a hashtable."
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

    $provider = $Context.Providers[$providerAlias]
    $result = $provider.CreateIdentity([string]$with.IdentityKey, $with.Attributes)

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

function Invoke-IdleStepEnsureAttribute {
    <#
    .SYNOPSIS
    Ensures that an identity attribute matches the desired value.

    .DESCRIPTION
    This is a provider-agnostic step. The host must supply a provider instance via
    Context.Providers[<ProviderAlias>]. The provider must implement an EnsureAttribute
    method with the signature (IdentityKey, Name, Value) and return an object that
    contains a boolean property 'Changed'.

    The step is idempotent by design: it converges state to the desired value.

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
    Normalized step object from the plan. Must contain a 'With' hashtable.

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
        throw "EnsureAttribute requires 'With' to be a hashtable."
    }

    foreach ($key in @('IdentityKey', 'Name', 'Value')) {
        if (-not $with.ContainsKey($key)) {
            throw "EnsureAttribute requires With.$key."
        }
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
        -MethodName 'EnsureAttribute' `
        -MethodArguments @([string]$with.IdentityKey, [string]$with.Name, $with.Value)

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

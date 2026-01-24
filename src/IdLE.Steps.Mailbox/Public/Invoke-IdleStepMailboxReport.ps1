function Invoke-IdleStepMailboxReport {
    <#
    .SYNOPSIS
    Retrieves mailbox details and returns a structured report.

    .DESCRIPTION
    This is a provider-agnostic step. The host must supply a provider instance via
    Context.Providers[<ProviderAlias>]. The provider must implement a GetMailbox
    method with the signature (IdentityKey, AuthSession) and return a mailbox object.

    The step is read-only and returns Changed = $false.

    Authentication:
    - If With.AuthSessionName is present, the step acquires an auth session via
      Context.AcquireAuthSession(Name, Options) and passes it to the provider method.
    - If With.AuthSessionName is absent, defaults to With.Provider value (e.g., 'ExchangeOnline').
    - With.AuthSessionOptions (optional, hashtable) is passed to the broker for
      session selection (e.g., @{ Role = 'Admin' }).

    .PARAMETER Context
    Execution context created by IdLE.Core.

    .PARAMETER Step
    Normalized step object from the plan. Must contain a 'With' hashtable.

    .OUTPUTS
    PSCustomObject (PSTypeName: IdLE.StepResult)

    .EXAMPLE
    # In workflow definition:
    @{
        Name = 'Report user mailbox'
        Type = 'IdLE.Step.Mailbox.Report'
        With = @{
            Provider      = 'ExchangeOnline'
            IdentityKey   = 'user@contoso.com'
        }
    }
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
        throw "Mailbox.Report requires 'With' to be a hashtable."
    }

    if (-not $with.ContainsKey('IdentityKey')) {
        throw "Mailbox.Report requires With.IdentityKey."
    }

    $providerAlias = if ($with.ContainsKey('Provider')) { [string]$with.Provider } else { 'ExchangeOnline' }

    if (-not ($Context.PSObject.Properties.Name -contains 'Providers')) {
        throw "Context does not contain a Providers hashtable."
    }
    if ($null -eq $Context.Providers -or -not ($Context.Providers -is [hashtable])) {
        throw "Context.Providers must be a hashtable."
    }
    if (-not $Context.Providers.ContainsKey($providerAlias)) {
        throw "Provider '$providerAlias' was not supplied by the host."
    }

    # Apply AuthSessionName convention: default to Provider if not specified
    if (-not $with.ContainsKey('AuthSessionName')) {
        $with['AuthSessionName'] = $providerAlias
    }

    $result = Invoke-IdleProviderMethod `
        -Context $Context `
        -With $with `
        -ProviderAlias $providerAlias `
        -MethodName 'GetMailbox' `
        -MethodArguments @([string]$with.IdentityKey)

    # Store mailbox data in State for downstream steps
    $state = @{
        Mailbox = $result
    }

    return [pscustomobject]@{
        PSTypeName = 'IdLE.StepResult'
        Name       = [string]$Step.Name
        Type       = [string]$Step.Type
        Status     = 'Completed'
        Changed    = $false
        Error      = $null
        State      = $state
    }
}

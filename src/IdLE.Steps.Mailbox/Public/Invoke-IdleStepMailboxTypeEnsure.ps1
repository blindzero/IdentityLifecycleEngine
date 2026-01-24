function Invoke-IdleStepMailboxTypeEnsure {
    <#
    .SYNOPSIS
    Ensures that a mailbox is of the desired type (User, Shared, Room, Equipment).

    .DESCRIPTION
    This is a provider-agnostic step. The host must supply a provider instance via
    Context.Providers[<ProviderAlias>]. The provider must implement an EnsureMailboxType
    method with the signature (IdentityKey, MailboxType, AuthSession) and return an object
    that contains a boolean property 'Changed'.

    The step is idempotent by design: it converges state to the desired type.

    Supported mailbox types:
    - User (regular user mailbox)
    - Shared (shared mailbox for team use)
    - Room (room resource mailbox)
    - Equipment (equipment resource mailbox)

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
    # In workflow definition (convert to shared mailbox):
    @{
        Name = 'Convert to shared mailbox'
        Type = 'IdLE.Step.Mailbox.Type.Ensure'
        With = @{
            Provider    = 'ExchangeOnline'
            IdentityKey = 'user@contoso.com'
            MailboxType = 'Shared'
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
        throw "Mailbox.Type.Ensure requires 'With' to be a hashtable."
    }

    foreach ($key in @('IdentityKey', 'MailboxType')) {
        if (-not $with.ContainsKey($key)) {
            throw "Mailbox.Type.Ensure requires With.$key."
        }
    }

    # Validate MailboxType
    $validTypes = @('User', 'Shared', 'Room', 'Equipment')
    if ($with.MailboxType -notin $validTypes) {
        throw "Mailbox.Type.Ensure requires With.MailboxType to be one of: $($validTypes -join ', '). Got: $($with.MailboxType)"
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
        -MethodName 'EnsureMailboxType' `
        -MethodArguments @([string]$with.IdentityKey, [string]$with.MailboxType)

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

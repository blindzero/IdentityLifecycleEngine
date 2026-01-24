function Invoke-IdleStepMailboxOutOfOfficeEnsure {
    <#
    .SYNOPSIS
    Ensures that a mailbox Out of Office (OOF) configuration matches the desired state.

    .DESCRIPTION
    This is a provider-agnostic step. The host must supply a provider instance via
    Context.Providers[<ProviderAlias>]. The provider must implement an EnsureOutOfOffice
    method with the signature (IdentityKey, Config, AuthSession) and return an object
    that contains a boolean property 'Changed'.

    The step is idempotent by design: it converges OOF configuration to the desired state.

    Out of Office Config shape (data-only hashtable):
    - Mode: 'Disabled' | 'Enabled' | 'Scheduled' (required)
    - Start: DateTime (required when Mode = 'Scheduled')
    - End: DateTime (required when Mode = 'Scheduled')
    - InternalMessage: string (optional)
    - ExternalMessage: string (optional)
    - ExternalAudience: 'None' | 'Known' | 'All' (optional, default provider-specific)

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
    # In workflow definition (enable OOF):
    @{
        Name = 'Enable Out of Office'
        Type = 'IdLE.Step.Mailbox.OutOfOffice.Ensure'
        With = @{
            Provider        = 'ExchangeOnline'
            IdentityKey     = 'user@contoso.com'
            Config          = @{
                Mode            = 'Enabled'
                InternalMessage = 'I am out of office.'
                ExternalMessage = 'I am currently unavailable.'
                ExternalAudience = 'All'
            }
        }
    }

    .EXAMPLE
    # In workflow definition (with template substitution for dynamic values):
    @{
        Name = 'Enable Out of Office for Leaver'
        Type = 'IdLE.Step.Mailbox.OutOfOffice.Ensure'
        With = @{
            Provider        = 'ExchangeOnline'
            IdentityKey     = '{{Request.Input.UserPrincipalName}}'
            Config          = @{
                Mode            = 'Enabled'
                InternalMessage = '{{Request.Input.DisplayName}} is no longer with the organization. For assistance, please contact {{Request.Input.ManagerEmail}}.'
                ExternalMessage = 'This person is no longer with the organization. Please contact the main office for assistance.'
                ExternalAudience = 'All'
            }
        }
    }
    # Note: Template substitution ({{...}}) happens during plan building.
    # Request.Input parameters are provided by the host when creating the lifecycle request.
    # Multi-line messages with line breaks are not currently supported in workflow configs
    # due to the data-only constraint. For complex formatting, consider external templates.

    .EXAMPLE
    # In workflow definition (scheduled OOF):
    @{
        Name = 'Schedule Out of Office'
        Type = 'IdLE.Step.Mailbox.OutOfOffice.Ensure'
        With = @{
            Provider        = 'ExchangeOnline'
            IdentityKey     = 'user@contoso.com'
            Config          = @{
                Mode            = 'Scheduled'
                Start           = '2025-02-01T00:00:00Z'
                End             = '2025-02-15T00:00:00Z'
                InternalMessage = 'I am on vacation until February 15.'
                ExternalMessage = 'I am currently out of office.'
            }
        }
    }

    .EXAMPLE
    # In workflow definition (disable OOF):
    @{
        Name = 'Disable Out of Office'
        Type = 'IdLE.Step.Mailbox.OutOfOffice.Ensure'
        With = @{
            Provider    = 'ExchangeOnline'
            IdentityKey = 'user@contoso.com'
            Config      = @{
                Mode = 'Disabled'
            }
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
        throw "Mailbox.OutOfOffice.Ensure requires 'With' to be a hashtable."
    }

    foreach ($key in @('IdentityKey', 'Config')) {
        if (-not $with.ContainsKey($key)) {
            throw "Mailbox.OutOfOffice.Ensure requires With.$key."
        }
    }

    $config = $with.Config
    if ($null -eq $config -or -not ($config -is [hashtable])) {
        throw "Mailbox.OutOfOffice.Ensure requires With.Config to be a hashtable."
    }

    # Validate Config shape
    if (-not $config.ContainsKey('Mode')) {
        throw "Mailbox.OutOfOffice.Ensure requires With.Config.Mode (Disabled, Enabled, or Scheduled)."
    }

    $validModes = @('Disabled', 'Enabled', 'Scheduled')
    if ($config.Mode -notin $validModes) {
        throw "Mailbox.OutOfOffice.Ensure requires With.Config.Mode to be one of: $($validModes -join ', '). Got: $($config.Mode)"
    }

    # Validate Scheduled mode requirements
    if ($config.Mode -eq 'Scheduled') {
        foreach ($key in @('Start', 'End')) {
            if (-not $config.ContainsKey($key)) {
                throw "Mailbox.OutOfOffice.Ensure with Mode 'Scheduled' requires With.Config.$key."
            }
        }
    }

    # Security: reject ScriptBlocks in Config (data-only constraint)
    foreach ($key in $config.Keys) {
        if ($config[$key] -is [ScriptBlock]) {
            throw "Mailbox.OutOfOffice.Ensure With.Config must not contain ScriptBlocks. Found ScriptBlock in key '$key'."
        }
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
        -MethodName 'EnsureOutOfOffice' `
        -MethodArguments @([string]$with.IdentityKey, $config)

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

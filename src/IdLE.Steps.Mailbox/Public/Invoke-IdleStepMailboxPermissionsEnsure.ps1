function Invoke-IdleStepMailboxPermissionsEnsure {
    <#
    .SYNOPSIS
    Ensures that mailbox delegate permissions match the desired state.

    .DESCRIPTION
    This is a provider-agnostic step. The host must supply a provider instance via
    Context.Providers[<ProviderAlias>]. The provider must implement an EnsureMailboxPermissions
    method with the signature (IdentityKey, Permissions, AuthSession) and return an object
    that contains a boolean property 'Changed'.

    The step is idempotent by design: it converges mailbox delegate permissions to the desired
    state by computing the delta between current and desired permissions and applying only the
    necessary changes.

    Supported rights (v1):
    - FullAccess
    - SendAs
    - SendOnBehalf

    Permissions array shape (data-only):
    Each entry must be a hashtable with:
    - AssignedUser: string (required) - UPN or SMTP address of the delegate
    - Right: 'FullAccess' | 'SendAs' | 'SendOnBehalf' (required)
    - Ensure: 'Present' | 'Absent' (required)

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
    # In workflow definition (grant FullAccess and SendAs):
    @{
        Name = 'Set Shared Mailbox Permissions'
        Type = 'IdLE.Step.Mailbox.EnsurePermissions'
        With = @{
            Provider    = 'ExchangeOnline'
            IdentityKey = 'shared@contoso.com'
            Permissions = @(
                @{ AssignedUser = 'user1@contoso.com'; Right = 'FullAccess'; Ensure = 'Present' }
                @{ AssignedUser = 'user2@contoso.com'; Right = 'SendAs';     Ensure = 'Present' }
            )
        }
    }

    .EXAMPLE
    # In workflow definition (revoke access):
    @{
        Name = 'Revoke Mailbox Access'
        Type = 'IdLE.Step.Mailbox.EnsurePermissions'
        With = @{
            Provider    = 'ExchangeOnline'
            IdentityKey = 'shared@contoso.com'
            Permissions = @(
                @{ AssignedUser = 'leaver@contoso.com'; Right = 'FullAccess';   Ensure = 'Absent' }
                @{ AssignedUser = 'leaver@contoso.com'; Right = 'SendOnBehalf'; Ensure = 'Absent' }
            )
        }
    }

    .EXAMPLE
    # With dynamic identity from request:
    @{
        Name = 'Grant Team Mailbox Access'
        Type = 'IdLE.Step.Mailbox.EnsurePermissions'
        With = @{
            Provider    = 'ExchangeOnline'
            IdentityKey = 'team@contoso.com'
            Permissions = @(
                @{ AssignedUser = @{ ValueFrom = 'Request.Intent.UserPrincipalName' }; Right = 'FullAccess'; Ensure = 'Present' }
            )
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
        throw "Mailbox.Permissions.Ensure requires 'With' to be a hashtable."
    }

    foreach ($key in @('IdentityKey', 'Permissions')) {
        if (-not $with.ContainsKey($key)) {
            throw "Mailbox.Permissions.Ensure requires With.$key."
        }
    }

    $permissions = $with.Permissions
    if ($null -eq $permissions) {
        throw "Mailbox.Permissions.Ensure requires With.Permissions to be an array."
    }

    # Accept single hashtable or array of hashtables
    if ($permissions -is [hashtable]) {
        $permissions = @($permissions)
    }

    $validRights = @('FullAccess', 'SendAs', 'SendOnBehalf')
    $validEnsure = @('Present', 'Absent')

    foreach ($entry in $permissions) {
        if ($null -eq $entry -or -not ($entry -is [hashtable])) {
            throw "Mailbox.Permissions.Ensure: each Permissions entry must be a hashtable."
        }
        foreach ($key in @('AssignedUser', 'Right', 'Ensure')) {
            if (-not $entry.ContainsKey($key)) {
                throw "Mailbox.Permissions.Ensure: each Permissions entry requires '$key'."
            }
        }
        if ($entry.Right -notin $validRights) {
            throw "Mailbox.Permissions.Ensure: Right must be one of: $($validRights -join ', '). Got: $($entry.Right)"
        }
        if ($entry.Ensure -notin $validEnsure) {
            throw "Mailbox.Permissions.Ensure: Ensure must be one of: $($validEnsure -join ', '). Got: $($entry.Ensure)"
        }
    }

    # Security: reject ScriptBlocks in Permissions (data-only constraint)
    Assert-IdleNoScriptBlock -InputObject $with.Permissions -Path 'With.Permissions'

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

    # Create execution-local copy of With to avoid mutating the plan
    $effectiveWith = $with.Clone()

    # Apply AuthSessionName convention: default to Provider if not specified
    if (-not $effectiveWith.ContainsKey('AuthSessionName')) {
        $effectiveWith['AuthSessionName'] = $providerAlias
    }

    $result = Invoke-IdleProviderMethod `
        -Context $Context `
        -With $effectiveWith `
        -ProviderAlias $providerAlias `
        -MethodName 'EnsureMailboxPermissions' `
        -MethodArguments @([string]$effectiveWith.IdentityKey, $permissions)

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

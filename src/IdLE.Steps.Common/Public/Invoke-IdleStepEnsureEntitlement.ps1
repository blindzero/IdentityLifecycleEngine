function Invoke-IdleStepEnsureEntitlement {
    <#
    .SYNOPSIS
    Ensures that an entitlement assignment is present or absent for an identity.

    .DESCRIPTION
    This provider-agnostic step uses entitlement provider contracts to converge
    an assignment to the desired state. The host must supply a provider instance
    via `Context.Providers[<ProviderAlias>]` that implements:

    - ListEntitlements(identityKey)
    - GrantEntitlement(identityKey, entitlement)
    - RevokeEntitlement(identityKey, entitlement)

    The step is idempotent and only calls Grant/Revoke when the assignment needs
    to change.

    Authentication:
    - If With.AuthSessionName is present, the step acquires an auth session via
      Context.AcquireAuthSession(Name, Options) and passes it to the provider methods
      if the provider supports an AuthSession parameter.
    - With.AuthSessionOptions (optional, hashtable) is passed to the broker for
      session selection (e.g., @{ Role = 'Tier0' }).
    - ScriptBlocks in AuthSessionOptions are rejected (security boundary).

    .PARAMETER Context
    Execution context created by IdLE.Core.

    .PARAMETER Step
    Normalized step object from the plan. Must contain a 'With' hashtable.

    .EXAMPLE
    Invoke-IdleStepEnsureEntitlement -Context $context -Step [pscustomobject]@{
        Name = 'Ensure group access'
        Type = 'IdLE.Step.EnsureEntitlement'
        With = @{
            IdentityKey = 'user1'
            Entitlement = @{ Kind = 'Group'; Id = 'example-group'; DisplayName = 'Example Group' }
            State       = 'Present'
            Provider    = 'Identity'
        }
    }

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

    function ConvertTo-IdleStepEntitlement {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [ValidateNotNull()]
            [object] $Value
        )

        $kind = $null
        $id = $null
        $displayName = $null

        if ($Value -is [System.Collections.IDictionary]) {
            $kind = $Value['Kind']
            $id = $Value['Id']
            if ($Value.Contains('DisplayName')) { $displayName = $Value['DisplayName'] }
        }
        else {
            $props = $Value.PSObject.Properties
            if ($props.Name -contains 'Kind') { $kind = $Value.Kind }
            if ($props.Name -contains 'Id') { $id = $Value.Id }
            if ($props.Name -contains 'DisplayName') { $displayName = $Value.DisplayName }
        }

        if ([string]::IsNullOrWhiteSpace([string]$kind)) {
            throw "EnsureEntitlement requires Entitlement.Kind."
        }
        if ([string]::IsNullOrWhiteSpace([string]$id)) {
            throw "EnsureEntitlement requires Entitlement.Id."
        }

        $normalized = [ordered]@{
            Kind = [string]$kind
            Id   = [string]$id
        }

        if ($null -ne $displayName -and -not [string]::IsNullOrWhiteSpace([string]$displayName)) {
            $normalized['DisplayName'] = [string]$displayName
        }

        return [pscustomobject]$normalized
    }

    function Test-IdleStepEntitlementEquals {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [ValidateNotNull()]
            [object] $A,

            [Parameter(Mandatory)]
            [ValidateNotNull()]
            [object] $B
        )

        $ea = ConvertTo-IdleStepEntitlement -Value $A
        $eb = ConvertTo-IdleStepEntitlement -Value $B

        if ($ea.Kind -ne $eb.Kind) {
            return $false
        }

        return [string]::Equals($ea.Id, $eb.Id, [System.StringComparison]::OrdinalIgnoreCase)
    }

    $with = $Step.With
    if ($null -eq $with -or -not ($with -is [hashtable])) {
        throw "EnsureEntitlement requires 'With' to be a hashtable."
    }

    foreach ($key in @('IdentityKey', 'Entitlement', 'State')) {
        if (-not $with.ContainsKey($key)) {
            throw "EnsureEntitlement requires With.$key."
        }
    }

    $stateRaw = [string]$with.State
    if ([string]::IsNullOrWhiteSpace($stateRaw)) {
        throw "EnsureEntitlement requires With.State to be 'Present' or 'Absent'."
    }

    $state = $stateRaw.Trim().ToLowerInvariant()
    if ($state -notin @('present', 'absent')) {
        throw "EnsureEntitlement With.State must be 'Present' or 'Absent'."
    }

    $entitlement = ConvertTo-IdleStepEntitlement -Value $with.Entitlement
    $identityKey = [string]$with.IdentityKey

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

    $requiredMethods = @('ListEntitlements')
    if ($state -eq 'present') {
        $requiredMethods += 'GrantEntitlement'
    }
    else {
        $requiredMethods += 'RevokeEntitlement'
    }

    foreach ($m in $requiredMethods) {
        if (-not ($provider.PSObject.Methods.Name -contains $m)) {
            throw "Provider '$providerAlias' must implement method '$m' for EnsureEntitlement."
        }
    }

    # Check AuthSession support for each method
    $listSupportsAuthSession = Test-IdleProviderMethodParameter -ProviderMethod $provider.PSObject.Methods['ListEntitlements'] -ParameterName 'AuthSession'
    $grantSupportsAuthSession = Test-IdleProviderMethodParameter -ProviderMethod $provider.PSObject.Methods['GrantEntitlement'] -ParameterName 'AuthSession'
    $revokeSupportsAuthSession = Test-IdleProviderMethodParameter -ProviderMethod $provider.PSObject.Methods['RevokeEntitlement'] -ParameterName 'AuthSession'

    if ($listSupportsAuthSession -and $null -ne $authSession) {
        $current = @($provider.ListEntitlements($identityKey, $authSession))
    }
    else {
        $current = @($provider.ListEntitlements($identityKey))
    }
    $matches = @($current | Where-Object { Test-IdleStepEntitlementEquals -A $_ -B $entitlement })

    $changed = $false

    if ($state -eq 'present') {
        if (@($matches).Count -eq 0) {
            if ($grantSupportsAuthSession -and $null -ne $authSession) {
                $result = $provider.GrantEntitlement($identityKey, $entitlement, $authSession)
            }
            else {
                $result = $provider.GrantEntitlement($identityKey, $entitlement)
            }
            if ($null -ne $result -and ($result.PSObject.Properties.Name -contains 'Changed')) {
                $changed = [bool]$result.Changed
            }
            else {
                $changed = $true
            }
        }
    }
    else {
        if (@($matches).Count -gt 0) {
            if ($revokeSupportsAuthSession -and $null -ne $authSession) {
                $result = $provider.RevokeEntitlement($identityKey, $entitlement, $authSession)
            }
            else {
                $result = $provider.RevokeEntitlement($identityKey, $entitlement)
            }
            if ($null -ne $result -and ($result.PSObject.Properties.Name -contains 'Changed')) {
                $changed = [bool]$result.Changed
            }
            else {
                $changed = $true
            }
        }
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

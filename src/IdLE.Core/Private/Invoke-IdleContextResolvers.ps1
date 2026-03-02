Set-StrictMode -Version Latest

function Invoke-IdleContextResolvers {
    <#
    .SYNOPSIS
    Executes ContextResolvers during plan building to populate Request.Context.

    .DESCRIPTION
    Runs each configured resolver in declared order, invoking the appropriate
    provider capability and writing the result under Request.Context at the
    predefined path for that capability (see Get-IdleCapabilityContextPath).

    Rules enforced:
    - Only capabilities in the read-only allow-list (Get-IdleReadOnlyCapabilities) may be used.
    - Each capability writes to a fixed, predefined path under Request.Context.
      The output path is not user-configurable.
    - Provider is selected by alias when 'With.Provider' is specified. When 'With.Provider'
      is omitted, auto-selection only succeeds if exactly one provider advertises the
      capability; zero matches or multiple matches both cause a fail-fast error.
    - Auth sessions are supported via With.AuthSessionName / With.AuthSessionOptions,
      using the AuthSessionBroker in Providers (same pattern as step execution).

    This function mutates Request.Context in place so that subsequent condition evaluation
    can reference the resolved data via 'Request.Context.*' paths.

    .PARAMETER Resolvers
    Array of resolver hashtables from the workflow definition. May be null or empty.

    .PARAMETER Providers
    Provider map passed to the plan (same format as -Providers on New-IdlePlanObject).
    May contain an AuthSessionBroker entry for auth session acquisition.

    .PARAMETER Request
    The lifecycle request object. Request.Context is mutated in place.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object[]] $Resolvers,

        [Parameter()]
        [AllowNull()]
        [object] $Providers,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Request
    )

    if ($null -eq $Resolvers -or @($Resolvers).Count -eq 0) {
        return
    }

    $readOnlyCapabilities = @(Get-IdleReadOnlyCapabilities)

    $i = 0
    foreach ($resolver in @($Resolvers)) {
        $resolverPath = "ContextResolvers[$i]"

        if ($null -eq $resolver -or -not ($resolver -is [System.Collections.IDictionary])) {
            throw [System.ArgumentException]::new("$resolverPath must be a hashtable.", 'Workflow')
        }

        # --- Capability ---
        if (-not $resolver.Contains('Capability') -or [string]::IsNullOrWhiteSpace([string]$resolver.Capability)) {
            throw [System.ArgumentException]::new("$resolverPath is missing required key 'Capability'.", 'Workflow')
        }

        $capability = [string]$resolver.Capability

        if ($readOnlyCapabilities -notcontains $capability) {
            $allowedList = $readOnlyCapabilities -join ', '
            throw [System.ArgumentException]::new(
                "ContextResolver capability '$capability' is not in the read-only allow-list. Allowed capabilities: $allowedList.",
                'Workflow'
            )
        }

        # --- With (optional, template-resolved) ---
        $with = if ($resolver.Contains('With') -and $null -ne $resolver.With) {
            Copy-IdleDataObject -Value $resolver.With
        }
        else {
            @{}
        }

        if ($with -isnot [System.Collections.IDictionary]) {
            throw [System.ArgumentException]::new("$resolverPath 'With' must be a hashtable.", 'Workflow')
        }

        # Resolve template placeholders in With values (e.g., {{Request.IdentityKeys.Id}}).
        $with = Resolve-IdleWorkflowTemplates -Value $with -Request $Request -StepName $resolverPath

        # --- Provider selection ---
        $providerAlias = if ($with -is [System.Collections.IDictionary] -and $with.Contains('Provider') -and -not [string]::IsNullOrWhiteSpace([string]$with.Provider)) {
            [string]$with.Provider
        }
        else {
            $null
        }

        $resolvedProviderAlias = Select-IdleResolverProviderAlias -Capability $capability -ProviderAlias $providerAlias -Providers $Providers -ResolverPath $resolverPath

        # --- Auth session (optional) ---
        # Supports With.AuthSessionName + With.AuthSessionOptions using the same pattern as steps.
        $authSession = $null
        $authBroker = Get-IdleAuthSessionBroker -Providers $Providers

        if ($with -is [System.Collections.IDictionary] -and $with.Contains('AuthSessionName')) {
            $sessionName = [string]$with.AuthSessionName
            $sessionOptions = if ($with.Contains('AuthSessionOptions')) { $with.AuthSessionOptions } else { $null }
            if ($null -ne $sessionOptions -and $sessionOptions -isnot [hashtable]) {
                throw [System.ArgumentException]::new("$resolverPath 'With.AuthSessionOptions' must be a hashtable.", 'Workflow')
            }

            if ($null -eq $authBroker) {
                throw [System.ArgumentException]::new(
                    "$resolverPath specifies With.AuthSessionName '$sessionName' but no AuthSessionBroker was found in Providers.",
                    'Providers'
                )
            }

            $authSession = $authBroker.AcquireAuthSession($sessionName, $sessionOptions)
        }
        elseif ($null -ne $authBroker) {
            # No explicit session name - try default acquisition for providers that require auth
            try {
                $authSession = $authBroker.AcquireAuthSession('', $null)
            }
            catch {
                $authSession = $null
            }
        }

        # --- Dispatch ---
        $result = Invoke-IdleResolverCapabilityDispatch `
            -Capability $capability `
            -ProviderAlias $resolvedProviderAlias `
            -Providers $Providers `
            -With $with `
            -AuthSession $authSession `
            -ResolverPath $resolverPath

        # --- Write to predefined Request.Context path ---
        $contextSubPath = Get-IdleCapabilityContextPath -Capability $capability
        Set-IdleContextValue -Context $Request.Context -Path $contextSubPath -Value $result

        $i++
    }
}

function Get-IdleAuthSessionBroker {
    <#
    .SYNOPSIS
    Extracts the AuthSessionBroker from a Providers map (if present).
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object] $Providers
    )

    if ($null -eq $Providers -or -not ($Providers -is [System.Collections.IDictionary])) {
        return $null
    }

    if ($Providers.ContainsKey('AuthSessionBroker')) {
        return $Providers['AuthSessionBroker']
    }

    return $null
}

function Select-IdleResolverProviderAlias {
    <#
    .SYNOPSIS
    Selects the provider alias for a context resolver capability.

    .DESCRIPTION
    If ProviderAlias is given, validates it exists in Providers and returns it.
    Otherwise, finds all providers advertising the capability, sorts them by alias
    for determinism, and returns the alias if exactly one matches. Throws an
    explicit ambiguity error when multiple providers match.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Capability,

        [Parameter()]
        [AllowNull()]
        [string] $ProviderAlias,

        [Parameter()]
        [AllowNull()]
        [object] $Providers,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $ResolverPath
    )

    if (-not [string]::IsNullOrWhiteSpace($ProviderAlias)) {
        # Explicit provider alias
        if ($null -eq $Providers -or -not ($Providers -is [System.Collections.IDictionary]) -or -not $Providers.ContainsKey($ProviderAlias)) {
            throw [System.ArgumentException]::new(
                "$ResolverPath references provider '$ProviderAlias' but no provider with that alias was found in the Providers map.",
                'Providers'
            )
        }

        return $ProviderAlias
    }

    # Auto-select: collect all providers advertising the capability (sorted by alias for determinism)
    $normalizedCapability = ConvertTo-IdleNormalizedCapability -Capability $Capability
    $matchingAliases = [System.Collections.Generic.List[string]]::new()

    if ($null -ne $Providers -and $Providers -is [System.Collections.IDictionary]) {
        $sortedAliases = @($Providers.Keys | Sort-Object)
        foreach ($alias in $sortedAliases) {
            $p = $Providers[$alias]
            if ($null -eq $p) { continue }
            if (-not ($p -is [psobject])) { continue }
            if (-not ($p.PSObject.Methods.Name -contains 'GetCapabilities')) { continue }

            $caps = $p.GetCapabilities()
            if ($null -eq $caps) { continue }

            $normalized = @(ConvertTo-IdleCapabilityList -Capabilities @($caps) -Normalize -Unique)
            if ($normalized -contains $normalizedCapability) {
                $matchingAliases.Add($alias)
            }
        }
    }

    if ($matchingAliases.Count -eq 1) {
        return $matchingAliases[0]
    }

    if ($matchingAliases.Count -gt 1) {
        $aliasList = $matchingAliases -join ', '
        throw [System.ArgumentException]::new(
            "${ResolverPath}: Multiple providers advertise capability '$Capability': $aliasList. Specify 'With.Provider' in the resolver to disambiguate.",
            'Providers'
        )
    }

    throw [System.ArgumentException]::new(
        "$ResolverPath requires capability '$Capability' but no provider in the Providers map advertises it.",
        'Providers'
    )
}

function Invoke-IdleResolverCapabilityDispatch {
    <#
    .SYNOPSIS
    Dispatches a read-only capability call to the provider.

    .DESCRIPTION
    Maps the capability identifier to the appropriate provider method and invokes it
    with parameters extracted from the With hashtable. Passes AuthSession to methods
    that support it (backwards-compatible).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Capability,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $ProviderAlias,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Providers,

        [Parameter()]
        [AllowNull()]
        [System.Collections.IDictionary] $With,

        [Parameter()]
        [AllowNull()]
        [object] $AuthSession,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $ResolverPath
    )

    $provider = $Providers[$ProviderAlias]

    switch ($Capability) {
        'IdLE.Entitlement.List' {
            if ($null -eq $With -or -not $With.Contains('IdentityKey') -or [string]::IsNullOrWhiteSpace([string]$With.IdentityKey)) {
                throw [System.ArgumentException]::new(
                    "$ResolverPath with capability 'IdLE.Entitlement.List' requires With.IdentityKey (non-empty string).",
                    'Workflow'
                )
            }

            $identityKey = [string]$With.IdentityKey

            $method = $provider.PSObject.Methods['ListEntitlements']
            if ($null -eq $method) {
                throw [System.InvalidOperationException]::new(
                    "${ResolverPath}: Provider '$ProviderAlias' does not implement 'ListEntitlements', which is required for capability 'IdLE.Entitlement.List'."
                )
            }

            $supportsAuthSession = Test-IdleProviderMethodParameter -ProviderMethod $method -ParameterName 'AuthSession'
            if ($supportsAuthSession -and $null -ne $AuthSession) {
                return @($provider.ListEntitlements($identityKey, $AuthSession))
            }
            return @($provider.ListEntitlements($identityKey))
        }

        'IdLE.Identity.Read' {
            if ($null -eq $With -or -not $With.Contains('IdentityKey') -or [string]::IsNullOrWhiteSpace([string]$With.IdentityKey)) {
                throw [System.ArgumentException]::new(
                    "$ResolverPath with capability 'IdLE.Identity.Read' requires With.IdentityKey (non-empty string).",
                    'Workflow'
                )
            }

            $identityKey = [string]$With.IdentityKey

            $method = $provider.PSObject.Methods['GetIdentity']
            if ($null -eq $method) {
                throw [System.InvalidOperationException]::new(
                    "${ResolverPath}: Provider '$ProviderAlias' does not implement 'GetIdentity', which is required for capability 'IdLE.Identity.Read'."
                )
            }

            $supportsAuthSession = Test-IdleProviderMethodParameter -ProviderMethod $method -ParameterName 'AuthSession'
            $identity = if ($supportsAuthSession -and $null -ne $AuthSession) {
                $provider.GetIdentity($identityKey, $AuthSession)
            }
            else {
                $provider.GetIdentity($identityKey)
            }

            # Flatten the identity object by promoting Attributes to the top level.
            # This allows users to access Request.Context.Identity.Profile.DisplayName
            # directly instead of Request.Context.Identity.Profile.Attributes.DisplayName.
            # The Attributes hashtable is removed after flattening.
            return ConvertTo-IdleFlattenedIdentity -Identity $identity
        }

        default {
            throw [System.InvalidOperationException]::new(
                "${ResolverPath}: No dispatch defined for capability '$Capability'. This is an engine bug."
            )
        }
    }
}

function Set-IdleContextValue {
    <#
    .SYNOPSIS
    Sets a value at a dotted path within a hashtable (the Request.Context).

    .DESCRIPTION
    Navigates the dotted path, creating new hashtables for missing intermediate nodes,
    and assigns the value at the leaf. Throws if an existing intermediate node is not
    a dictionary (prevents silently discarding host-provided context).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [System.Collections.IDictionary] $Context,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Path,

        [Parameter()]
        [AllowNull()]
        [object] $Value
    )

    $segments = $Path -split '\.'

    if ($segments.Count -eq 1) {
        $Context[$segments[0]] = $Value
        return
    }

    # Navigate/create intermediate hashtables
    $current = $Context
    for ($idx = 0; $idx -lt $segments.Count - 1; $idx++) {
        $seg = $segments[$idx]
        $existing = if ($current -is [System.Collections.IDictionary] -and $current.Contains($seg)) { $current[$seg] } else { $null }

        if ($null -eq $existing) {
            # Create a new intermediate hashtable when there is no existing value.
            $current[$seg] = @{}
        }
        elseif (-not ($existing -is [System.Collections.IDictionary])) {
            throw [System.InvalidOperationException]::new(
                ("Cannot set context path '{0}': intermediate node '{1}' is of type '{2}', expected a hashtable. Use a unique resolver output path to avoid conflicts with existing context data." -f $Path, $seg, $existing.GetType().FullName)
            )
        }

        $current = $current[$seg]
    }

    $current[$segments[-1]] = $Value
}

function ConvertTo-IdleFlattenedIdentity {
    <#
    .SYNOPSIS
    Flattens an identity object by promoting Attributes to top-level properties.

    .DESCRIPTION
    Takes an identity object returned by a provider (with IdentityKey, Enabled, Attributes)
    and creates a new object where:
    - IdentityKey and Enabled are preserved at the top level
    - All properties from the Attributes hashtable are promoted to top-level properties
    - The original Attributes hashtable is removed after flattening

    Reserved property names (IdentityKey, Enabled) will not be overwritten
    if they appear as keys in the Attributes hashtable. If a conflict occurs, a verbose
    warning is emitted and the conflicting attribute is skipped.

    This allows users to access Request.Context.Identity.Profile.DisplayName
    directly at the top level.

    .PARAMETER Identity
    The identity object returned by a provider's GetIdentity method.

    .OUTPUTS
    PSCustomObject with flattened attributes.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [object] $Identity
    )

    if ($null -eq $Identity) {
        return $null
    }

    # Clone the original identity object to preserve all existing properties and PSTypeName
    $cloned = [ordered]@{}
    
    # Capture PSTypeName(s) from the original object if it's a PSCustomObject
    $typeNames = @()
    if ($Identity -isnot [System.Collections.IDictionary]) {
        foreach ($typeName in $Identity.PSObject.TypeNames) {
            if ($typeName -ne 'System.Management.Automation.PSCustomObject' -and $typeName -ne 'System.Object') {
                $typeNames += $typeName
            }
        }
    }
    
    # Copy all properties from the original object
    if ($Identity -is [System.Collections.IDictionary]) {
        foreach ($key in $Identity.Keys) {
            if ($key -ne 'PSTypeName') {
                $cloned[$key] = $Identity[$key]
            }
        }
        # Also check for PSTypeName in the hashtable
        if ($Identity.ContainsKey('PSTypeName')) {
            $typeNames += $Identity['PSTypeName']
        }
    }
    else {
        foreach ($prop in $Identity.PSObject.Properties) {
            $cloned[$prop.Name] = $prop.Value
        }
    }
    
    # Add PSTypeName to the cloned hashtable if we captured any
    if ($typeNames.Count -gt 0) {
        $cloned['PSTypeName'] = $typeNames[0]  # Primary type name
    }
    
    # Convert to PSCustomObject
    $flattened = [pscustomobject]$cloned

    # Promote all attribute keys to top level.
    # Reserved property names (IdentityKey, Enabled) will not be overwritten
    # if they appear as keys in the Attributes hashtable.
    $attributes = $null
    if ($flattened.PSObject.Properties.Name -contains 'Attributes') {
        $attributes = $flattened.Attributes
    }
    
    if ($null -ne $attributes -and $attributes -is [System.Collections.IDictionary]) {
        $reservedNames = @('IdentityKey', 'Enabled')
        foreach ($key in $attributes.Keys) {
            # Only add if not already present (existing properties take precedence)
            if ($flattened.PSObject.Properties.Name -notcontains $key) {
                $flattened | Add-Member -MemberType NoteProperty -Name $key -Value $attributes[$key] -Force
            }
            elseif ($reservedNames -contains $key) {
                # Warn if an attribute key conflicts with a reserved property name
                # This helps users understand why an attribute was skipped
                Write-Verbose "Identity attribute '$key' conflicts with a core property name and will be skipped during flattening."
            }
        }
    }
    
    # Always remove the Attributes property after flattening (no backward compatibility)
    # This applies whether Attributes was null, empty, or had content
    if ($flattened.PSObject.Properties.Name -contains 'Attributes') {
        $flattened.PSObject.Properties.Remove('Attributes')
    }

    return $flattened
}

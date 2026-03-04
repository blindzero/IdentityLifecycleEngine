Set-StrictMode -Version Latest

function Invoke-IdleContextResolvers {
    <#
    .SYNOPSIS
    Executes ContextResolvers during plan building to populate Request.Context.

    .DESCRIPTION
    Runs each configured resolver in declared order, invoking the appropriate
    provider capability and writing the result under Request.Context using a
    provider/auth-scoped namespace as the source of truth, with engine-defined
    Views for common aggregation patterns.

    Rules enforced:
    - Only capabilities in the read-only allow-list (Get-IdleReadOnlyCapabilities) may be used.
    - Results are written to the provider/auth-scoped path:
        Request.Context.Providers.<ProviderAlias>.<AuthSessionKey>.<CapabilitySubPath>
      where AuthSessionKey is 'Default' when With.AuthSessionName is not specified.
    - Engine-defined Views are (re)built deterministically after each resolver:
        Request.Context.Views.<CapabilitySubPath>               (global: all providers/sessions)
        Request.Context.Views.Providers.<ProviderAlias>.<...>   (provider: all sessions)
      View semantics are capability-specific; currently only IdLE.Entitlement.List has views.
    - For IdLE.Entitlement.List, each entry is annotated with SourceProvider and
      SourceAuthSessionName to enable auditing and source-specific filtering.
    - Provider alias and AuthSessionKey must be valid context path segments.
    - Provider is selected by alias when 'With.Provider' is specified. When 'With.Provider'
      is omitted, auto-selection only succeeds if exactly one provider advertises the
      capability; zero matches or multiple matches both cause a fail-fast error.
    - Auth sessions are supported via With.AuthSessionName / With.AuthSessionOptions,
      using the AuthSessionBroker in Providers (same pattern as step execution).

    This function mutates Request.Context in place so that subsequent condition evaluation
    can reference the resolved data via scoped paths or Views.

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

        # --- Validate provider alias as a context path segment ---
        Assert-IdleContextPathSegment -Value $resolvedProviderAlias -Label 'Provider alias' -ResolverPath $resolverPath

        # --- Auth session (optional) ---
        # Supports With.AuthSessionName + With.AuthSessionOptions using the same pattern as steps.
        $authSession = $null
        $authBroker = Get-IdleAuthSessionBroker -Providers $Providers
        $authSessionKey = 'Default'

        if ($with -is [System.Collections.IDictionary] -and $with.Contains('AuthSessionName') -and -not [string]::IsNullOrWhiteSpace([string]$with.AuthSessionName)) {
            $sessionName = [string]$with.AuthSessionName
            $authSessionKey = $sessionName
            $sessionOptions = if ($with.Contains('AuthSessionOptions')) { $with.AuthSessionOptions } else { $null }
            if ($null -ne $sessionOptions -and $sessionOptions -isnot [hashtable]) {
                throw [System.ArgumentException]::new("$resolverPath 'With.AuthSessionOptions' must be a hashtable.", 'Workflow')
            }

            # --- Validate auth session key as a context path segment ---
            Assert-IdleContextPathSegment -Value $authSessionKey -Label 'AuthSessionName' -ResolverPath $resolverPath

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

        # --- Annotate entitlement results with source metadata ---
        if ($capability -eq 'IdLE.Entitlement.List') {
            $result = @(Add-IdleEntitlementSourceMetadata -Entitlements @($result) -SourceProvider $resolvedProviderAlias -SourceAuthSessionName $authSessionKey)
        }

        # --- Write to provider/auth-scoped path (source of truth) ---
        # Path: Providers.<ProviderAlias>.<AuthSessionKey>.<CapabilitySubPath>
        $contextSubPath = Get-IdleCapabilityContextPath -Capability $capability
        $scopedPath = "Providers.$resolvedProviderAlias.$authSessionKey.$contextSubPath"
        Set-IdleContextValue -Context $Request.Context -Path $scopedPath -Value $result

        # --- Rebuild deterministic Views for capabilities with defined view semantics ---
        Build-IdleContextResolverViews -Context $Request.Context -Capability $capability -CapabilitySubPath $contextSubPath

        $i++
    }
}

function Assert-IdleContextPathSegment {
    <#
    .SYNOPSIS
    Validates that a value is a valid context path segment (no dots, valid identifier characters).

    .DESCRIPTION
    Context path segments are used to build hierarchical paths in Request.Context.
    They must not contain dots (path separators) and must match a safe identifier pattern.

    .PARAMETER Value
    The value to validate.

    .PARAMETER Label
    Human-readable label for error messages (e.g., 'Provider alias', 'AuthSessionName').

    .PARAMETER ResolverPath
    The resolver path (e.g., 'ContextResolvers[0]') for error context.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Value,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Label,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $ResolverPath
    )

    if ($Value -notmatch '^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$') {
        throw [System.ArgumentException]::new(
            ('{0}: {1} ''{2}'' is not a valid context path segment. Must start with alphanumeric, followed by alphanumeric, hyphens, or underscores (max 64 chars total, no dots allowed).' -f $ResolverPath, $Label, $Value),
            'Workflow'
        )
    }
}

function Add-IdleEntitlementSourceMetadata {
    <#
    .SYNOPSIS
    Annotates each entitlement entry with SourceProvider and SourceAuthSessionName metadata.

    .DESCRIPTION
    Ensures every entitlement returned by IdLE.Entitlement.List resolvers carries source
    information to support auditing, per-provider filtering, and merged view semantics.

    .PARAMETER Entitlements
    Array of entitlement objects (hashtables or PSCustomObjects).

    .PARAMETER SourceProvider
    The provider alias that produced these entitlements.

    .PARAMETER SourceAuthSessionName
    The auth session key used ('Default' if no explicit session was specified).

    .OUTPUTS
    Object[]
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter()]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]] $Entitlements,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $SourceProvider,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $SourceAuthSessionName
    )

    if ($null -eq $Entitlements -or $Entitlements.Count -eq 0) {
        return @()
    }

    $result = [System.Collections.Generic.List[object]]::new()
    foreach ($item in $Entitlements) {
        if ($null -eq $item) {
            # Skip null entries; provider implementations must not return null items in an entitlement list.
            continue
        }

        if ($item -is [System.Collections.IDictionary]) {
            $enriched = @{}
            foreach ($key in $item.Keys) { $enriched[$key] = $item[$key] }
            $enriched['SourceProvider'] = $SourceProvider
            $enriched['SourceAuthSessionName'] = $SourceAuthSessionName
            $result.Add($enriched)
        }
        else {
            # PSCustomObject or other reference type — add properties non-destructively
            $item | Add-Member -MemberType NoteProperty -Name 'SourceProvider' -Value $SourceProvider -Force
            $item | Add-Member -MemberType NoteProperty -Name 'SourceAuthSessionName' -Value $SourceAuthSessionName -Force
            $result.Add($item)
        }
    }

    return @($result)
}

function Build-IdleContextResolverViews {
    <#
    .SYNOPSIS
    Rebuilds engine-defined Views in Request.Context for capabilities with defined view semantics.

    .DESCRIPTION
    Views are deterministic, engine-defined aggregations of scoped resolver outputs.
    Called after each resolver execution to keep views current.

    Currently only IdLE.Entitlement.List has defined view semantics:
      - Global view:   Request.Context.Views.Identity.Entitlements
                       (merge of all provider/session scoped lists, sorted by ProviderAlias then AuthSessionKey)
      - Provider view: Request.Context.Views.Providers.<ProviderAlias>.Identity.Entitlements
                       (merge of all session scoped lists for that provider)

    No view is defined for IdLE.Identity.Read; results are only in the scoped path.

    .PARAMETER Context
    The Request.Context hashtable to update.

    .PARAMETER Capability
    The capability identifier (e.g., 'IdLE.Entitlement.List').

    .PARAMETER CapabilitySubPath
    The capability sub-path (e.g., 'Identity.Entitlements').
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [System.Collections.IDictionary] $Context,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Capability,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $CapabilitySubPath
    )

    # Only IdLE.Entitlement.List has defined view semantics.
    if ($Capability -ne 'IdLE.Entitlement.List') {
        return
    }

    $globalList = [System.Collections.Generic.List[object]]::new()
    $perProviderLists = @{}

    $providersNode = if ($Context.Contains('Providers')) { $Context['Providers'] } else { $null }
    if ($null -ne $providersNode -and $providersNode -is [System.Collections.IDictionary]) {
        # Stable ordering: sorted by ProviderAlias, then AuthSessionKey
        $sortedProviders = @($providersNode.Keys | Sort-Object)
        foreach ($providerAlias in $sortedProviders) {
            $providerNode = $providersNode[$providerAlias]
            if ($null -eq $providerNode -or -not ($providerNode -is [System.Collections.IDictionary])) { continue }

            $sortedAuthKeys = @($providerNode.Keys | Sort-Object)
            foreach ($authKey in $sortedAuthKeys) {
                $authNode = $providerNode[$authKey]
                if ($null -eq $authNode -or -not ($authNode -is [System.Collections.IDictionary])) { continue }

                # Navigate the CapabilitySubPath within the auth node
                $items = Get-IdleValueByPath -Object $authNode -Path $CapabilitySubPath
                if ($null -eq $items) { continue }

                $itemArray = @($items)
                if ($itemArray.Count -eq 0) { continue }

                foreach ($item in $itemArray) {
                    $globalList.Add($item)
                }

                if (-not $perProviderLists.Contains($providerAlias)) {
                    $perProviderLists[$providerAlias] = [System.Collections.Generic.List[object]]::new()
                }
                foreach ($item in $itemArray) {
                    $perProviderLists[$providerAlias].Add($item)
                }
            }
        }
    }

    # Global view: Request.Context.Views.<CapabilitySubPath>
    Set-IdleContextValue -Context $Context -Path "Views.$CapabilitySubPath" -Value @($globalList)

    # Provider views: Request.Context.Views.Providers.<ProviderAlias>.<CapabilitySubPath>
    foreach ($providerAlias in $perProviderLists.Keys) {
        Set-IdleContextValue -Context $Context -Path "Views.Providers.$providerAlias.$CapabilitySubPath" -Value @($perProviderLists[$providerAlias])
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
            if ($supportsAuthSession -and $null -ne $AuthSession) {
                return $provider.GetIdentity($identityKey, $AuthSession)
            }
            return $provider.GetIdentity($identityKey)
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

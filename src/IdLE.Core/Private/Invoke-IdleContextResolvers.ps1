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
    - Provider is selected by alias when 'Provider' is specified; otherwise the first
      provider that advertises the capability is used.

    This function mutates Request.Context in place so that subsequent condition evaluation
    can reference the resolved data via 'Request.Context.*' paths.

    .PARAMETER Resolvers
    Array of resolver hashtables from the workflow definition. May be null or empty.

    .PARAMETER Providers
    Provider map passed to the plan (same format as -Providers on New-IdlePlanObject).

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
        $providerAlias = if ($resolver.Contains('Provider') -and -not [string]::IsNullOrWhiteSpace([string]$resolver.Provider)) {
            [string]$resolver.Provider
        }
        else {
            $null
        }

        $provider = Select-IdleResolverProvider -Capability $capability -ProviderAlias $providerAlias -Providers $Providers -ResolverPath $resolverPath

        # --- Dispatch ---
        $result = Invoke-IdleResolverCapabilityDispatch -Capability $capability -Provider $provider -With $with -ResolverPath $resolverPath

        # --- Write to predefined Request.Context path ---
        $contextSubPath = Get-IdleCapabilityContextPath -Capability $capability
        Set-IdleContextValue -Context $Request.Context -Path $contextSubPath -Value $result

        $i++
    }
}

function Select-IdleResolverProvider {
    <#
    .SYNOPSIS
    Selects the appropriate provider for a context resolver capability.

    .DESCRIPTION
    If ProviderAlias is given, looks up that key in Providers.
    Otherwise, selects the first provider that advertises the capability.
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

        return $Providers[$ProviderAlias]
    }

    # Auto-select: find first provider advertising the capability
    $providerInstances = @(Get-IdleProvidersFromMap -Providers $Providers)

    foreach ($p in $providerInstances) {
        if ($null -eq $p) { continue }
        if (-not ($p.PSObject.Methods.Name -contains 'GetCapabilities')) { continue }

        $caps = $p.GetCapabilities()
        if ($null -eq $caps) { continue }

        $normalized = @(ConvertTo-IdleCapabilityList -Capabilities @($caps) -Normalize -Unique)
        $normalizedCapability = ConvertTo-IdleNormalizedCapability -Capability $Capability

        if ($normalized -contains $normalizedCapability) {
            return $p
        }
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
    with parameters extracted from the With hashtable.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Capability,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Provider,

        [Parameter()]
        [AllowNull()]
        [System.Collections.IDictionary] $With,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $ResolverPath
    )

    switch ($Capability) {
        'IdLE.Entitlement.List' {
            if ($null -eq $With -or -not $With.Contains('IdentityKey') -or [string]::IsNullOrWhiteSpace([string]$With.IdentityKey)) {
                throw [System.ArgumentException]::new(
                    "$ResolverPath with capability 'IdLE.Entitlement.List' requires With.IdentityKey (non-empty string).",
                    'Workflow'
                )
            }

            $identityKey = [string]$With.IdentityKey

            if (-not ($Provider.PSObject.Methods.Name -contains 'ListEntitlements')) {
                throw [System.InvalidOperationException]::new(
                    "${ResolverPath}: Provider does not implement 'ListEntitlements', which is required for capability 'IdLE.Entitlement.List'."
                )
            }

            return @($Provider.ListEntitlements($identityKey))
        }

        'IdLE.Identity.Read' {
            if ($null -eq $With -or -not $With.Contains('IdentityKey') -or [string]::IsNullOrWhiteSpace([string]$With.IdentityKey)) {
                throw [System.ArgumentException]::new(
                    "$ResolverPath with capability 'IdLE.Identity.Read' requires With.IdentityKey (non-empty string).",
                    'Workflow'
                )
            }

            $identityKey = [string]$With.IdentityKey

            if (-not ($Provider.PSObject.Methods.Name -contains 'GetIdentity')) {
                throw [System.InvalidOperationException]::new(
                    "${ResolverPath}: Provider does not implement 'GetIdentity', which is required for capability 'IdLE.Identity.Read'."
                )
            }

            return $Provider.GetIdentity($identityKey)
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
    Navigates the dotted path, creating intermediate hashtables as needed,
    and assigns the value at the leaf node.
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

        if ($null -eq $existing -or -not ($existing -is [System.Collections.IDictionary])) {
            $current[$seg] = @{}
        }

        $current = $current[$seg]
    }

    $current[$segments[-1]] = $Value
}

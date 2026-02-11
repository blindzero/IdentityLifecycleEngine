function Invoke-IdleStepEnsureAttributes {
    <#
    .SYNOPSIS
    Ensures that multiple identity attributes match their desired values.

    .DESCRIPTION
    This is a provider-agnostic step that can ensure multiple attributes in a single step.
    The host must supply a provider instance via Context.Providers[<ProviderAlias>].

    Provider interaction strategy:
    1. If the provider implements EnsureAttributes(IdentityKey, AttributesHashtable), it is called once (fast path).
    2. Otherwise, the step falls back to calling EnsureAttribute(IdentityKey, Name, Value) for each attribute.

    The step is idempotent by design: it converges state to the desired values.

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

    $with = $null
    if ($Step.PSObject.Properties.Name -contains 'With') {
        $with = $Step.With
    }
    
    if ($null -eq $with -or -not ($with -is [hashtable])) {
        throw "EnsureAttributes requires 'With' to be a hashtable."
    }

    if (-not $with.ContainsKey('IdentityKey')) {
        throw "EnsureAttributes requires With.IdentityKey."
    }

    if (-not $with.ContainsKey('Attributes')) {
        throw "EnsureAttributes requires With.Attributes."
    }

    $attributes = $with.Attributes
    if ($null -eq $attributes -or -not ($attributes -is [hashtable])) {
        throw "EnsureAttributes requires With.Attributes to be a hashtable."
    }

    if ($attributes.Count -eq 0) {
        throw "EnsureAttributes requires With.Attributes to contain at least one attribute."
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
    
    # Check if provider has EnsureAttributes method (fast path)
    $hasEnsureAttributes = $null -ne $provider.PSObject.Methods['EnsureAttributes']
    
    $anyChanged = $false
    $attributeResults = @()
    
    if ($hasEnsureAttributes) {
        # Fast path: call EnsureAttributes once
        $result = Invoke-IdleProviderMethod `
            -Context $Context `
            -With $with `
            -ProviderAlias $providerAlias `
            -MethodName 'EnsureAttributes' `
            -MethodArguments @([string]$with.IdentityKey, $attributes)
        
        if ($null -ne $result -and ($result.PSObject.Properties.Name -contains 'Changed')) {
            $anyChanged = [bool]$result.Changed
        }
        
        # If provider returns per-attribute details, use them
        if ($null -ne $result -and ($result.PSObject.Properties.Name -contains 'Attributes')) {
            $attributeResults = $result.Attributes
        } else {
            # Provider doesn't return per-attribute details, so we can't determine individual attribute changes
            # Report overall status but mark individual attribute change status as unknown
            foreach ($key in $attributes.Keys) {
                $attributeResults += @{
                    Name    = $key
                    Changed = $anyChanged  # Overall result - individual changes unknown without provider details
                    Error   = $null
                }
            }
        }
    }
    else {
        # Fallback: call EnsureAttribute for each attribute
        foreach ($key in $attributes.Keys) {
            $attrName = [string]$key
            $attrValue = $attributes[$key]
            
            try {
                $result = Invoke-IdleProviderMethod `
                    -Context $Context `
                    -With $with `
                    -ProviderAlias $providerAlias `
                    -MethodName 'EnsureAttribute' `
                    -MethodArguments @([string]$with.IdentityKey, $attrName, $attrValue)
                
                $changed = $false
                if ($null -ne $result -and ($result.PSObject.Properties.Name -contains 'Changed')) {
                    $changed = [bool]$result.Changed
                }
                
                if ($changed) {
                    $anyChanged = $true
                }
                
                $attributeResults += @{
                    Name    = $attrName
                    Changed = $changed
                    Error   = $null
                }
            }
            catch {

                throw
            }
        }
    }

    return [pscustomobject]@{
        PSTypeName = 'IdLE.StepResult'
        Name       = [string]$Step.Name
        Type       = [string]$Step.Type
        Status     = 'Completed'
        Changed    = $anyChanged
        Error      = $null
        Data       = @{
            Attributes = $attributeResults
        }
    }
}

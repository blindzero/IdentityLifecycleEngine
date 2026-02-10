function Invoke-IdleStepEnsureAttribute {
    <#
    .SYNOPSIS
    Ensures that an identity attribute matches the desired value.

    .DESCRIPTION
    [DEPRECATED] This step type is deprecated. Use IdLE.Step.EnsureAttributes instead.

    This is a compatibility wrapper that delegates to Invoke-IdleStepEnsureAttributes.
    It converts the singular With.Name/With.Value syntax to the plural With.Attributes
    hashtable format.

    The host must supply a provider instance via Context.Providers[<ProviderAlias>].
    The provider must implement an EnsureAttribute method with the signature
    (IdentityKey, Name, Value) and return an object that contains a boolean property 'Changed'.

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

    # Convert singular syntax to plural format
    $attributeName = [string]$with.Name
    $attributeValue = $with.Value
    
    $pluralWith = $with.Clone()
    $pluralWith.Remove('Name')
    $pluralWith.Remove('Value')
    $pluralWith['Attributes'] = @{
        $attributeName = $attributeValue
    }
    
    $pluralStep = [pscustomobject]@{
        Name = $Step.Name
        Type = 'IdLE.Step.EnsureAttributes'
        With = $pluralWith
    }
    
    # Delegate to plural handler
    $result = Invoke-IdleStepEnsureAttributes -Context $Context -Step $pluralStep
    
    # Preserve the original step type in the result
    $result.Type = [string]$Step.Type
    
    return $result
}

function Invoke-IdleStepEnsureAttributes {
    <#
    .SYNOPSIS
    Ensures that multiple identity attributes match their desired values.

    .DESCRIPTION
    This is a provider-agnostic step that can ensure multiple attributes in a single step.
    The engine passes the provider resolved from With.Provider (default 'Identity') as -Provider.

    Provider interaction strategy:
    1. If the provider implements EnsureAttributes(IdentityKey, AttributesHashtable), it is called once (fast path).
    2. Otherwise, the step falls back to calling EnsureAttribute(IdentityKey, Name, Value) for each attribute.

    The step is idempotent by design: it converges state to the desired values.

    Authentication is handled by the engine (With.AuthSessionName, With.AuthSessionOptions).

    .PARAMETER With
    Validated With hashtable: IdentityKey, Attributes (non-empty hashtable of attribute name -> value).

    .PARAMETER Provider
    Provider handle created by the engine (see docs/extend/steps.md).

    .OUTPUTS
    System.Collections.Hashtable (Changed, Data.Attributes)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable] $With,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Provider
    )

    $identityKey = [string]$With.IdentityKey
    $attributes = $With.Attributes
    if ($attributes.Count -eq 0) {
        throw "EnsureAttributes requires With.Attributes to contain at least one attribute."
    }

    $anyChanged = $false
    $attributeResults = @()

    if ($Provider.HasMethod('EnsureAttributes')) {
        # Fast path: one provider call for all attributes.
        $result = $Provider.Invoke('EnsureAttributes', @($identityKey, $attributes))

        if ($null -ne $result -and ($result.PSObject.Properties.Name -contains 'Changed')) {
            $anyChanged = [bool]$result.Changed
        }

        if ($null -ne $result -and ($result.PSObject.Properties.Name -contains 'Attributes')) {
            $attributeResults = $result.Attributes
        }
        else {
            # Without per-attribute details from the provider, report the overall result per attribute.
            foreach ($key in $attributes.Keys) {
                $attributeResults += @{
                    Name    = $key
                    Changed = $anyChanged
                    Error   = $null
                }
            }
        }
    }
    else {
        foreach ($key in $attributes.Keys) {
            $attrName = [string]$key

            # A typed object array keeps a $null value as positional argument ("clear attribute").
            $callArguments = [object[]]::new(3)
            $callArguments[0] = $identityKey
            $callArguments[1] = $attrName
            $callArguments[2] = $attributes[$key]

            $result = $Provider.Invoke('EnsureAttribute', $callArguments)

            $changed = $null -ne $result -and ($result.PSObject.Properties.Name -contains 'Changed') -and [bool]$result.Changed
            if ($changed) {
                $anyChanged = $true
            }

            $attributeResults += @{
                Name    = $attrName
                Changed = $changed
                Error   = $null
            }
        }
    }

    return @{
        Changed = $anyChanged
        Data    = @{ Attributes = $attributeResults }
    }
}

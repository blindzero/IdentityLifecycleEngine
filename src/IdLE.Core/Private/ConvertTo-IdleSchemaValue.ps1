function ConvertTo-IdleSchemaValue {
    <#
    .SYNOPSIS
    Validates a value against a key schema and returns the normalized value.

    .DESCRIPTION
    Key schema properties: Type (String, Int, Bool, Hashtable, Array, Any), Required, Default,
    AllowedValues, AllowEmpty, Keys, AllowAdditionalKeys, Items (see docs/extend/steps.md).

    Normalization:
    - Hashtable keys declared in Keys use the declared casing; Defaults are applied for absent keys.
    - String values matching AllowedValues (case-insensitive) use the declared casing.
    - Optional keys with a $null value are treated as absent.

    No implicit type coercion is performed. Failures throw an ArgumentException whose message starts with
    WithKeyMissing, WithKeyUnknown, WithKeyTypeMismatch or WithValueNotAllowed.

    .PARAMETER Schema
    Key schema hashtable.

    .PARAMETER Value
    Value to validate.

    .PARAMETER Path
    Path used in error messages (e.g. 'With.Entitlement.Kind').

    .PARAMETER ErrorPrefix
    Context prefix used in error messages (e.g. "Step 'Disable' (type 'IdLE.Step.DisableIdentity')").

    .PARAMETER ExcludedKeys
    Hashtable keys that are never accepted as additional keys (common keys of steps without a Provider).

    .OUTPUTS
    The normalized value.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable] $Schema,

        [Parameter()]
        [AllowNull()]
        [object] $Value,

        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [string] $ErrorPrefix,

        [Parameter()]
        [string[]] $ExcludedKeys = @()
    )

    function New-IdleSchemaError {
        param([string] $Code, [string] $Text)
        return [System.ArgumentException]::new("${Code}: $ErrorPrefix $Text", 'Workflow')
    }

    $type = [string]$Schema['Type']
    $actualType = if ($null -eq $Value) { 'null' } else { $Value.GetType().Name }

    switch ($type) {
        'Any' {
            return $Value
        }

        'String' {
            if ($Value -isnot [string]) {
                throw (New-IdleSchemaError 'WithKeyTypeMismatch' "$Path must be a String (got $actualType).")
            }
            if ($Value -eq '' -and -not ($Schema['AllowEmpty'] -eq $true)) {
                throw (New-IdleSchemaError 'WithValueNotAllowed' "$Path must not be empty.")
            }
            if ($Schema.ContainsKey('AllowedValues')) {
                foreach ($allowed in @($Schema['AllowedValues'])) {
                    if ([string]::Equals([string]$allowed, $Value, [System.StringComparison]::OrdinalIgnoreCase)) {
                        return [string]$allowed
                    }
                }
                $allowedList = [string]::Join(', ', @($Schema['AllowedValues']))
                throw (New-IdleSchemaError 'WithValueNotAllowed' "$Path must be one of: $allowedList (got '$Value').")
            }
            return $Value
        }

        'Int' {
            if (($Value -isnot [int] -and $Value -isnot [long])) {
                throw (New-IdleSchemaError 'WithKeyTypeMismatch' "$Path must be an Int (got $actualType).")
            }
            if ($Schema.ContainsKey('AllowedValues') -and @($Schema['AllowedValues']) -notcontains $Value) {
                $allowedList = [string]::Join(', ', @($Schema['AllowedValues']))
                throw (New-IdleSchemaError 'WithValueNotAllowed' "$Path must be one of: $allowedList (got $Value).")
            }
            return $Value
        }

        'Bool' {
            if ($Value -isnot [bool]) {
                throw (New-IdleSchemaError 'WithKeyTypeMismatch' "$Path must be a Bool (got $actualType).")
            }
            return $Value
        }

        'Array' {
            if ($null -eq $Value -or $Value -is [string] -or $Value -is [System.Collections.IDictionary] -or $Value -isnot [System.Collections.IEnumerable]) {
                throw (New-IdleSchemaError 'WithKeyTypeMismatch' "$Path must be an Array (got $actualType).")
            }
            $items = @($Value)
            if ($items.Count -eq 0 -and -not ($Schema['AllowEmpty'] -eq $true)) {
                throw (New-IdleSchemaError 'WithValueNotAllowed' "$Path must not be empty.")
            }
            if (-not $Schema.ContainsKey('Items')) {
                return , $items
            }
            $result = [System.Collections.Generic.List[object]]::new()
            for ($index = 0; $index -lt $items.Count; $index++) {
                $itemPath = "$Path[$index]"
                if ($null -eq $items[$index]) {
                    throw (New-IdleSchemaError 'WithKeyTypeMismatch' "$itemPath must not be null.")
                }
                $result.Add((ConvertTo-IdleSchemaValue -Schema $Schema['Items'] -Value $items[$index] -Path $itemPath -ErrorPrefix $ErrorPrefix))
            }
            return , $result.ToArray()
        }

        'Hashtable' {
            if ($Value -isnot [System.Collections.IDictionary]) {
                throw (New-IdleSchemaError 'WithKeyTypeMismatch' "$Path must be a Hashtable (got $actualType).")
            }
            if (-not $Schema.ContainsKey('Keys')) {
                # No declared keys: free-form content (e.g. attribute maps).
                return $Value
            }

            $declared = $Schema['Keys']
            $allowAdditional = $Schema['AllowAdditionalKeys'] -eq $true
            $result = [hashtable]::new([System.StringComparer]::OrdinalIgnoreCase)

            foreach ($inputKey in @($Value.PSBase.Keys)) {
                $keyName = [string]$inputKey
                $declaredKey = @($declared.PSBase.Keys | Where-Object { [string]::Equals([string]$_, $keyName, [System.StringComparison]::OrdinalIgnoreCase) }) | Select-Object -First 1
                if ($null -eq $declaredKey) {
                    if (-not $allowAdditional -or $ExcludedKeys -contains $keyName) {
                        $supported = [string]::Join(', ', @($declared.PSBase.Keys | Sort-Object))
                        throw (New-IdleSchemaError 'WithKeyUnknown' "$Path.$keyName is not supported. Supported keys: $supported.")
                    }
                    $result[$keyName] = $Value[$inputKey]
                    continue
                }

                $inputValue = $Value[$inputKey]
                if ($null -eq $inputValue) {
                    # Optional keys set to $null are treated as absent (Required keys are checked below).
                    continue
                }

                $result[[string]$declaredKey] = ConvertTo-IdleSchemaValue -Schema $declared[$declaredKey] -Value $inputValue -Path "$Path.$declaredKey" -ErrorPrefix $ErrorPrefix
            }

            foreach ($declaredKey in @($declared.PSBase.Keys | Sort-Object)) {
                if ($result.ContainsKey([string]$declaredKey)) { continue }

                $keySchema = $declared[$declaredKey]
                if ($keySchema['Required'] -eq $true) {
                    throw (New-IdleSchemaError 'WithKeyMissing' "$Path.$declaredKey is required.")
                }
                if ($keySchema.ContainsKey('Default')) {
                    $result[[string]$declaredKey] = Copy-IdleDataObject -Value $keySchema['Default']
                }
            }

            return $result
        }

        default {
            throw [System.InvalidOperationException]::new("Unsupported schema type '$type' at $Path.")
        }
    }
}

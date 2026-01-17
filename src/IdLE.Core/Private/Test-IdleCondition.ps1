function Test-IdleCondition {
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Context', Justification = 'Used for path resolution within nested helper functions.')]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable] $Condition,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Context
    )

    # Evaluates a declarative Condition (data-only) against the provided context.
    #
    # Supported schema (validated by Test-IdleConditionSchema):
    # - Groups: All | Any | None  (each contains an array/list of condition nodes)
    # - Operators:
    #   - Equals    = @{ Path = '<path>'; Value  = <value>  }
    #   - NotEquals = @{ Path = '<path>'; Value  = <value>  }
    #   - Exists    = '<path>' OR @{ Path = '<path>' }
    #   - In        = @{ Path = '<path>'; Values = <array|scalar> }
    #
    # Paths are resolved via Get-IdleValueByPath against the provided $Context.
    # For readability in configuration, a leading "context." prefix is ignored.

    $schemaErrors = Test-IdleConditionSchema -Condition $Condition -StepName $null
    if (@($schemaErrors).Count -gt 0) {
        $msg = "Condition schema validation failed: {0}" -f ([string]::Join(' ', @($schemaErrors)))
        throw [System.ArgumentException]::new($msg, 'Condition')
    }

    function Resolve-IdleConditionPathValue {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $Path
        )

        # Allow "context." prefix for readability in config files.
        $effectivePath = if ($Path.StartsWith('context.')) { $Path.Substring(8) } else { $Path }

        return Get-IdleValueByPath -Object $Context -Path $effectivePath
    }

    function Test-IdleConditionNode {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [ValidateNotNull()]
            [System.Collections.IDictionary] $Node
        )

        # GROUPS
        if ($Node.Contains('All')) {
            foreach ($child in @($Node.All)) {
                if (-not (Test-IdleConditionNode -Node ([System.Collections.IDictionary]$child))) {
                    return $false
                }
            }
            return $true
        }

        if ($Node.Contains('Any')) {
            foreach ($child in @($Node.Any)) {
                if (Test-IdleConditionNode -Node ([System.Collections.IDictionary]$child)) {
                    return $true
                }
            }
            return $false
        }

        if ($Node.Contains('None')) {
            foreach ($child in @($Node.None)) {
                if (Test-IdleConditionNode -Node ([System.Collections.IDictionary]$child)) {
                    return $false
                }
            }
            return $true
        }

        # OPERATORS
        if ($Node.Contains('Equals')) {
            $op = $Node.Equals

            $actual = Resolve-IdleConditionPathValue -Path ([string]$op.Path)
            $expected = $op.Value

            # Stable semantics: compare as strings (keeps config predictable across providers/types).
            return ([string]$actual -eq [string]$expected)
        }

        if ($Node.Contains('NotEquals')) {
            $op = $Node.NotEquals

            $actual = Resolve-IdleConditionPathValue -Path ([string]$op.Path)
            $expected = $op.Value

            return ([string]$actual -ne [string]$expected)
        }

        if ($Node.Contains('Exists')) {
            $existsVal = $Node.Exists

            $path = if ($existsVal -is [string]) {
                [string]$existsVal
            } else {
                [string]$existsVal.Path
            }

            $value = Resolve-IdleConditionPathValue -Path $path
            return ($null -ne $value)
        }

        if ($Node.Contains('In')) {
            $op = $Node.In

            $actual = Resolve-IdleConditionPathValue -Path ([string]$op.Path)
            $values = $op.Values

            if ($null -eq $values) {
                return $false
            }

            # Treat scalar and array uniformly.
            $candidates = if ($values -is [System.Collections.IEnumerable] -and -not ($values -is [string])) {
                @($values)
            } else {
                @($values)
            }

            foreach ($candidate in $candidates) {
                if ([string]$actual -eq [string]$candidate) {
                    return $true
                }
            }

            return $false
        }

        # Should never happen due to schema validation.
        return $false
    }

    return (Test-IdleConditionNode -Node $Condition)
}

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
    #   - Equals       = @{ Path = '<path>'; Value   = <value>   }
    #   - NotEquals    = @{ Path = '<path>'; Value   = <value>   }
    #   - Exists       = '<path>' OR @{ Path = '<path>' }
    #   - In           = @{ Path = '<path>'; Values  = <array|scalar> }
    #   - Contains     = @{ Path = '<path>'; Value   = <value>   }
    #   - NotContains  = @{ Path = '<path>'; Value   = <value>   }
    #   - Like         = @{ Path = '<path>'; Pattern = <pattern> }
    #   - NotLike      = @{ Path = '<path>'; Pattern = <pattern> }
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

        if ($Node.Contains('Contains')) {
            $op = $Node.Contains

            $actual = Resolve-IdleConditionPathValue -Path ([string]$op.Path)
            $expected = $op.Value

            # Contains requires the resolved path to be a list.
            if ($null -eq $actual) {
                return $false
            }

            if (-not ($actual -is [System.Collections.IEnumerable]) -or ($actual -is [string])) {
                throw [System.ArgumentException]::new(
                    ("Contains operator requires Path to resolve to a list, but got '{0}'." -f $actual.GetType().Name),
                    'Condition'
                )
            }

            # Check if any element in the list matches the expected value (case-insensitive).
            foreach ($item in @($actual)) {
                if ([string]$item -eq [string]$expected) {
                    return $true
                }
            }

            return $false
        }

        if ($Node.Contains('NotContains')) {
            $op = $Node.NotContains

            $actual = Resolve-IdleConditionPathValue -Path ([string]$op.Path)
            $expected = $op.Value

            # NotContains requires the resolved path to be a list.
            if ($null -eq $actual) {
                return $true
            }

            if (-not ($actual -is [System.Collections.IEnumerable]) -or ($actual -is [string])) {
                throw [System.ArgumentException]::new(
                    ("NotContains operator requires Path to resolve to a list, but got '{0}'." -f $actual.GetType().Name),
                    'Condition'
                )
            }

            # Check if no element in the list matches the expected value (case-insensitive).
            foreach ($item in @($actual)) {
                if ([string]$item -eq [string]$expected) {
                    return $false
                }
            }

            return $true
        }

        if ($Node.Contains('Like')) {
            $op = $Node.Like

            $actual = Resolve-IdleConditionPathValue -Path ([string]$op.Path)
            $pattern = $op.Pattern

            if ($null -eq $actual) {
                return $false
            }

            # If the value is a list, return true if ANY element matches the pattern.
            if (($actual -is [System.Collections.IEnumerable]) -and -not ($actual -is [string])) {
                foreach ($item in @($actual)) {
                    if ([string]$item -like [string]$pattern) {
                        return $true
                    }
                }
                return $false
            }

            # Scalar: direct pattern match (case-insensitive by default).
            return ([string]$actual -like [string]$pattern)
        }

        if ($Node.Contains('NotLike')) {
            $op = $Node.NotLike

            $actual = Resolve-IdleConditionPathValue -Path ([string]$op.Path)
            $pattern = $op.Pattern

            if ($null -eq $actual) {
                return $true
            }

            # If the value is a list, return true if NO element matches the pattern.
            if (($actual -is [System.Collections.IEnumerable]) -and -not ($actual -is [string])) {
                foreach ($item in @($actual)) {
                    if ([string]$item -like [string]$pattern) {
                        return $false
                    }
                }
                return $true
            }

            # Scalar: direct pattern non-match (case-insensitive by default).
            return ([string]$actual -notlike [string]$pattern)
        }

        # Should never happen due to schema validation.
        return $false
    }

    return (Test-IdleConditionNode -Node $Condition)
}

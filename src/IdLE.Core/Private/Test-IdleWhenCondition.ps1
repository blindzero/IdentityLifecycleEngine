function Test-IdleWhenCondition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable] $When,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Context
    )

    # Evaluates a declarative When condition (data-only) against the current execution context.
    #
    # Supported schema (validated by Test-IdleWhenConditionSchema):
    # - Groups: All | Any | None  (each contains an array/list of condition nodes)
    # - Operators:
    #   - Equals    = @{ Left = '<path>'; Right = <value> }
    #   - NotEquals = @{ Left = '<path>'; Right = <value> }
    #   - Exists    = '<path>' OR @{ Path = '<path>' }
    #   - In        = @{ Left = '<path>'; Right = <array|scalar> }
    #
    # Paths are resolved via Get-IdleValueByPath against the provided $Context.
    # For convenience, a leading "context." prefix is ignored (e.g. "context.DesiredState.Department").
    #
    # This function is intentionally strict and throws on invalid schema.

    $schemaErrors = Test-IdleWhenConditionSchema -When $When -StepName $null
    if ($schemaErrors.Count -gt 0) {
        $msg = "When condition schema validation failed: {0}" -f ([string]::Join(' ', @($schemaErrors)))
        throw [System.ArgumentException]::new($msg, 'When')
    }

    function Resolve-IdleWhenPathValue {
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

    function Test-IdleWhenNode {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [ValidateNotNull()]
            [System.Collections.IDictionary] $Node
        )

        # GROUPS
        if ($Node.Contains('All')) {
            foreach ($child in @($Node.All)) {
                if (-not (Test-IdleWhenNode -Node ([System.Collections.IDictionary]$child))) {
                    return $false
                }
            }
            return $true
        }

        if ($Node.Contains('Any')) {
            foreach ($child in @($Node.Any)) {
                if (Test-IdleWhenNode -Node ([System.Collections.IDictionary]$child)) {
                    return $true
                }
            }
            return $false
        }

        if ($Node.Contains('None')) {
            foreach ($child in @($Node.None)) {
                if (Test-IdleWhenNode -Node ([System.Collections.IDictionary]$child)) {
                    return $false
                }
            }
            return $true
        }

        # OPERATORS
        if ($Node.Contains('Equals')) {
            $op = $Node.Equals
            $leftValue = Resolve-IdleWhenPathValue -Path ([string]$op.Left)
            $rightValue = $op.Right

            # Keep semantics simple and stable: string comparison.
            return ([string]$leftValue -eq [string]$rightValue)
        }

        if ($Node.Contains('NotEquals')) {
            $op = $Node.NotEquals
            $leftValue = Resolve-IdleWhenPathValue -Path ([string]$op.Left)
            $rightValue = $op.Right

            return ([string]$leftValue -ne [string]$rightValue)
        }

        if ($Node.Contains('Exists')) {
            $existsVal = $Node.Exists

            $path = if ($existsVal -is [string]) {
                [string]$existsVal
            } else {
                [string]$existsVal.Path
            }

            $value = Resolve-IdleWhenPathValue -Path $path
            return ($null -ne $value)
        }

        if ($Node.Contains('In')) {
            $op = $Node.In
            $leftValue = Resolve-IdleWhenPathValue -Path ([string]$op.Left)

            $right = $op.Right
            if ($null -eq $right) { return $false }

            # Treat scalar and array uniformly.
            $candidates = if ($right -is [System.Collections.IEnumerable] -and -not ($right -is [string])) {
                @($right)
            } else {
                @($right)
            }

            foreach ($candidate in $candidates) {
                if ([string]$leftValue -eq [string]$candidate) {
                    return $true
                }
            }

            return $false
        }

        # Should never happen due to schema validation.
        return $false
    }

    return (Test-IdleWhenNode -Node $When)
}

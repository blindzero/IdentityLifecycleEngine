function Test-IdleConditionSchema {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable] $Condition,

        [Parameter()]
        [AllowNull()]
        [string] $StepName
    )

    # NOTE:
    # This validator is intentionally strict:
    # - Unknown keys are errors (keeps configuration deterministic and toolable).
    # - A node must be either a group (All/Any/None) OR an operator (Equals/NotEquals/Exists/In).
    # - ScriptBlocks are validated elsewhere (Assert-IdleNoScriptBlock). We assume data-only input here.
    #
    # Supported operator shapes:
    # - Equals    = @{ Path = '<path>'; Value  = <value>  }
    # - NotEquals = @{ Path = '<path>'; Value  = <value>  }
    # - Exists    = '<path>' OR @{ Path = '<path>' }
    # - In        = @{ Path = '<path>'; Values = <array|scalar> }

    $errors = [System.Collections.Generic.List[string]]::new()

    $prefix = if ([string]::IsNullOrWhiteSpace($StepName)) { 'Step' } else { "Step '$StepName'" }

    function Add-IdleConditionError {
        param(
            [Parameter(Mandatory)]
            [ValidateNotNull()]
            [object] $List,

            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $Message
        )

        if ($List -is [System.Collections.Generic.List[string]]) {
            $null = $List.Add($Message)
            return
        }

        if ($List -is [System.Collections.ArrayList]) {
            $null = $List.Add($Message)
            return
        }

        throw [System.InvalidOperationException]::new(
            ("Add-IdleConditionError expected a mutable list type but got '{0}'." -f $List.GetType().FullName)
        )
    }

    function Test-IdleConditionNodeSchema {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [ValidateNotNull()]
            [object] $Node,

            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $NodePath
        )

        $nodeErrors = [System.Collections.Generic.List[string]]::new()

        if (-not ($Node -is [System.Collections.IDictionary])) {
            Add-IdleConditionError -List $nodeErrors -Message ("{0}: Condition node must be a hashtable/dictionary." -f $NodePath)
            return ,$nodeErrors
        }

        $allowedGroupKeys = @('All', 'Any', 'None')
        $allowedOpKeys    = @('Equals', 'NotEquals', 'Exists', 'In')
        $allowedKeys      = @($allowedGroupKeys + $allowedOpKeys)

        $presentGroupKeys = @($allowedGroupKeys | Where-Object { $Node.Contains($_) })
        $presentOpKeys    = @($allowedOpKeys | Where-Object { $Node.Contains($_) })

        # Enforce: either group OR operator, never both.
        if ($presentGroupKeys.Count -gt 0 -and $presentOpKeys.Count -gt 0) {
            Add-IdleConditionError -List $nodeErrors -Message ("{0}: Condition node must be either a group (All/Any/None) or an operator (Equals/NotEquals/Exists/In), not both." -f $NodePath)
            return ,$nodeErrors
        }

        # Enforce: at least one recognized key.
        if ($presentGroupKeys.Count -eq 0 -and $presentOpKeys.Count -eq 0) {
            Add-IdleConditionError -List $nodeErrors -Message ("{0}: Condition node must specify one group (All/Any/None) or one operator (Equals/NotEquals/Exists/In)." -f $NodePath)
            return ,$nodeErrors
        }

        # Enforce: exactly one key at this level (avoids ambiguous evaluation).
        if (($presentGroupKeys.Count + $presentOpKeys.Count) -ne 1) {
            Add-IdleConditionError -List $nodeErrors -Message ("{0}: Condition node must specify exactly one group/operator key." -f $NodePath)
            return ,$nodeErrors
        }

        # Unknown keys are errors.
        foreach ($k in @($Node.Keys)) {
            if ($allowedKeys -notcontains [string]$k) {
                Add-IdleConditionError -List $nodeErrors -Message ("{0}: Unknown key '{1}' in condition node." -f $NodePath, [string]$k)
            }
        }

        if ($nodeErrors.Count -gt 0) {
            return ,$nodeErrors
        }

        # GROUP: All/Any/None must be a non-empty array/list of condition nodes.
        if ($presentGroupKeys.Count -eq 1) {
            $groupKey = [string]$presentGroupKeys[0]
            $children = $Node[$groupKey]
            $groupPath = ("{0}.{1}" -f $NodePath, $groupKey)

            if ($null -eq $children) {
                Add-IdleConditionError -List $nodeErrors -Message ("{0}: Group value must not be null and must contain at least one condition." -f $groupPath)
                return ,$nodeErrors
            }

            if (-not ($children -is [System.Collections.IEnumerable]) -or ($children -is [string])) {
                Add-IdleConditionError -List $nodeErrors -Message ("{0}: Group value must be an array/list of condition nodes." -f $groupPath)
                return ,$nodeErrors
            }

            $i = 0
            $count = 0
            foreach ($child in @($children)) {
                $count++
                foreach ($e in (Test-IdleConditionNodeSchema -Node $child -NodePath ("{0}[{1}]" -f $groupPath, $i))) {
                    Add-IdleConditionError -List $nodeErrors -Message $e
                }
                $i++
            }

            if ($count -lt 1) {
                Add-IdleConditionError -List $nodeErrors -Message ("{0}: Group must contain at least one condition node." -f $groupPath)
            }

            return ,$nodeErrors
        }

        # OPERATOR: Exactly one of Equals/NotEquals/Exists/In.
        $opKey  = [string]$presentOpKeys[0]
        $opVal  = $Node[$opKey]
        $opPath = ("{0}.{1}" -f $NodePath, $opKey)

        switch ($opKey) {
            'Equals' {
                if (-not ($opVal -is [System.Collections.IDictionary])) {
                    Add-IdleConditionError -List $nodeErrors -Message ("{0}: Equals must be a hashtable with keys Path and Value." -f $opPath)
                    return ,$nodeErrors
                }

                foreach ($k in @($opVal.Keys)) {
                    if (@('Path', 'Value') -notcontains [string]$k) {
                        Add-IdleConditionError -List $nodeErrors -Message ("{0}: Unknown key '{1}'. Allowed: Path, Value." -f $opPath, [string]$k)
                    }
                }

                if (-not $opVal.Contains('Path') -or [string]::IsNullOrWhiteSpace([string]$opVal.Path)) {
                    Add-IdleConditionError -List $nodeErrors -Message ("{0}: Missing or empty Path." -f $opPath)
                }

                if (-not $opVal.Contains('Value')) {
                    Add-IdleConditionError -List $nodeErrors -Message ("{0}: Missing Value." -f $opPath)
                }

                return ,$nodeErrors
            }

            'NotEquals' {
                if (-not ($opVal -is [System.Collections.IDictionary])) {
                    Add-IdleConditionError -List $nodeErrors -Message ("{0}: NotEquals must be a hashtable with keys Path and Value." -f $opPath)
                    return ,$nodeErrors
                }

                foreach ($k in @($opVal.Keys)) {
                    if (@('Path', 'Value') -notcontains [string]$k) {
                        Add-IdleConditionError -List $nodeErrors -Message ("{0}: Unknown key '{1}'. Allowed: Path, Value." -f $opPath, [string]$k)
                    }
                }

                if (-not $opVal.Contains('Path') -or [string]::IsNullOrWhiteSpace([string]$opVal.Path)) {
                    Add-IdleConditionError -List $nodeErrors -Message ("{0}: Missing or empty Path." -f $opPath)
                }

                if (-not $opVal.Contains('Value')) {
                    Add-IdleConditionError -List $nodeErrors -Message ("{0}: Missing Value." -f $opPath)
                }

                return ,$nodeErrors
            }

            'Exists' {
                # Exists operator supports two forms:
                #   Exists = 'context.Attributes.mail'
                #   Exists = @{ Path = 'context.Attributes.mail' }
                if ($opVal -is [string]) {
                    if ([string]::IsNullOrWhiteSpace([string]$opVal)) {
                        Add-IdleConditionError -List $nodeErrors -Message ("{0}: Exists path must be a non-empty string." -f $opPath)
                    }
                    return ,$nodeErrors
                }

                if (-not ($opVal -is [System.Collections.IDictionary])) {
                    Add-IdleConditionError -List $nodeErrors -Message ("{0}: Exists must be a string path or a hashtable with key Path." -f $opPath)
                    return ,$nodeErrors
                }

                foreach ($k in @($opVal.Keys)) {
                    if (@('Path') -notcontains [string]$k) {
                        Add-IdleConditionError -List $nodeErrors -Message ("{0}: Unknown key '{1}'. Allowed: Path." -f $opPath, [string]$k)
                    }
                }

                if (-not $opVal.Contains('Path') -or [string]::IsNullOrWhiteSpace([string]$opVal.Path)) {
                    Add-IdleConditionError -List $nodeErrors -Message ("{0}: Missing or empty Path." -f $opPath)
                }

                return ,$nodeErrors
            }

            'In' {
                # In operator:
                #   In = @{ Path = 'context.Identity.Type'; Values = @('Joiner','Mover') }
                if (-not ($opVal -is [System.Collections.IDictionary])) {
                    Add-IdleConditionError -List $nodeErrors -Message ("{0}: In must be a hashtable with keys Path and Values." -f $opPath)
                    return ,$nodeErrors
                }

                foreach ($k in @($opVal.Keys)) {
                    if (@('Path', 'Values') -notcontains [string]$k) {
                        Add-IdleConditionError -List $nodeErrors -Message ("{0}: Unknown key '{1}'. Allowed: Path, Values." -f $opPath, [string]$k)
                    }
                }

                if (-not $opVal.Contains('Path') -or [string]::IsNullOrWhiteSpace([string]$opVal.Path)) {
                    Add-IdleConditionError -List $nodeErrors -Message ("{0}: Missing or empty Path." -f $opPath)
                }

                if (-not $opVal.Contains('Values')) {
                    Add-IdleConditionError -List $nodeErrors -Message ("{0}: Missing Values." -f $opPath)
                    return ,$nodeErrors
                }

                $values = $opVal.Values
                if ($null -eq $values) {
                    Add-IdleConditionError -List $nodeErrors -Message ("{0}: Values must not be null." -f $opPath)
                    return ,$nodeErrors
                }

                # Values should be list/array (or scalar) but must not be a dictionary (ambiguous).
                if ($values -is [System.Collections.IDictionary]) {
                    Add-IdleConditionError -List $nodeErrors -Message ("{0}: Values must be a list/array (or scalar), not a dictionary." -f $opPath)
                }

                return ,$nodeErrors
            }
        }

        Add-IdleConditionError -List $nodeErrors -Message ("{0}: Unsupported operator '{1}'." -f $NodePath, $opKey)
        return ,$nodeErrors
    }

    foreach ($e in (Test-IdleConditionNodeSchema -Node $Condition -NodePath ("{0}: Condition" -f $prefix))) {
        Add-IdleConditionError -List $errors -Message $e
    }

    return ,$errors
}

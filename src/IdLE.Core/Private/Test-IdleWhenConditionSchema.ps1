function Test-IdleWhenConditionSchema {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable] $When,

        [Parameter()]
        [AllowNull()]
        [string] $StepName
    )

    # NOTE:
    # This validator is intentionally strict:
    # - Unknown keys are errors (keeps configuration deterministic and toolable).
    # - A node must be either a group (All/Any/None) OR an operator (Equals/NotEquals/Exists/In).
    # - ScriptBlocks are validated elsewhere (Assert-IdleNoScriptBlock). We assume data-only input here.

    $errors = [System.Collections.Generic.List[string]]::new()
    $prefix = if ([string]::IsNullOrWhiteSpace($StepName)) { 'Step' } else { "Step '$StepName'" }

    function Add-IdleWhenError {
        param(
            [Parameter(Mandatory)]
            [System.Collections.Generic.List[string]] $List,

            [Parameter(Mandatory)]
            [string] $Message
        )

        $null = $List.Add($Message)
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
            Add-IdleWhenError -List $nodeErrors -Message ("{0}: Condition node must be a hashtable/dictionary." -f $NodePath)
            return $nodeErrors
        }

        $allowedGroupKeys = @('All', 'Any', 'None')
        $allowedOpKeys    = @('Equals', 'NotEquals', 'Exists', 'In')
        $allowedKeys      = @($allowedGroupKeys + $allowedOpKeys)

        $presentGroupKeys = @($allowedGroupKeys | Where-Object { $Node.Contains($_) })
        $presentOpKeys    = @($allowedOpKeys | Where-Object { $Node.Contains($_) })

        # Enforce: either group OR operator, never both.
        if ($presentGroupKeys.Count -gt 0 -and $presentOpKeys.Count -gt 0) {
            Add-IdleWhenError -List $nodeErrors -Message ("{0}: Condition node must be either a group (All/Any/None) or an operator (Equals/NotEquals/Exists/In), not both." -f $NodePath)
            return $nodeErrors
        }

        # Enforce: at least one recognized key.
        if ($presentGroupKeys.Count -eq 0 -and $presentOpKeys.Count -eq 0) {
            Add-IdleWhenError -List $nodeErrors -Message ("{0}: Condition node must specify one group (All/Any/None) or one operator (Equals/NotEquals/Exists/In)." -f $NodePath)
            return $nodeErrors
        }

        # Enforce: exactly one key at this level (avoids ambiguous evaluation).
        if (($presentGroupKeys.Count + $presentOpKeys.Count) -ne 1) {
            Add-IdleWhenError -List $nodeErrors -Message ("{0}: Condition node must specify exactly one group/operator key." -f $NodePath)
            return $nodeErrors
        }

        # Unknown keys are errors.
        foreach ($k in @($Node.Keys)) {
            if ($allowedKeys -notcontains [string]$k) {
                Add-IdleWhenError -List $nodeErrors -Message ("{0}: Unknown key '{1}' in condition node." -f $NodePath, [string]$k)
            }
        }

        if ($nodeErrors.Count -gt 0) {
            return $nodeErrors
        }

        # GROUP: All/Any/None must be a non-empty array/list of condition nodes.
        if ($presentGroupKeys.Count -eq 1) {
            $groupKey = [string]$presentGroupKeys[0]
            $children = $Node[$groupKey]
            $groupPath = ("{0}.{1}" -f $NodePath, $groupKey)

            if ($null -eq $children) {
                Add-IdleWhenError -List $nodeErrors -Message ("{0}: Group value must not be null and must contain at least one condition." -f $groupPath)
                return $nodeErrors
            }

            if (-not ($children -is [System.Collections.IEnumerable]) -or ($children -is [string])) {
                Add-IdleWhenError -List $nodeErrors -Message ("{0}: Group value must be an array/list of condition nodes." -f $groupPath)
                return $nodeErrors
            }

            $i = 0
            $count = 0
            foreach ($child in @($children)) {
                $count++
                foreach ($e in (Test-IdleConditionNodeSchema -Node $child -NodePath ("{0}[{1}]" -f $groupPath, $i))) {
                    Add-IdleWhenError -List $nodeErrors -Message $e
                }
                $i++
            }

            if ($count -lt 1) {
                Add-IdleWhenError -List $nodeErrors -Message ("{0}: Group must contain at least one condition node." -f $groupPath)
            }

            return $nodeErrors
        }

        # OPERATOR: Exactly one of Equals/NotEquals/Exists/In.
        $opKey  = [string]$presentOpKeys[0]
        $opVal  = $Node[$opKey]
        $opPath = ("{0}.{1}" -f $NodePath, $opKey)

        switch ($opKey) {
            'Equals' {
                if (-not ($opVal -is [System.Collections.IDictionary])) {
                    Add-IdleWhenError -List $nodeErrors -Message ("{0}: Equals must be a hashtable with keys Left and Right." -f $opPath)
                    return $nodeErrors
                }

                foreach ($k in @($opVal.Keys)) {
                    if (@('Left', 'Right') -notcontains [string]$k) {
                        Add-IdleWhenError -List $nodeErrors -Message ("{0}: Unknown key '{1}'. Allowed: Left, Right." -f $opPath, [string]$k)
                    }
                }

                if (-not $opVal.Contains('Left') -or [string]::IsNullOrWhiteSpace([string]$opVal.Left)) {
                    Add-IdleWhenError -List $nodeErrors -Message ("{0}: Missing or empty Left." -f $opPath)
                }

                if (-not $opVal.Contains('Right')) {
                    Add-IdleWhenError -List $nodeErrors -Message ("{0}: Missing Right." -f $opPath)
                }

                return $nodeErrors
            }

            'NotEquals' {
                if (-not ($opVal -is [System.Collections.IDictionary])) {
                    Add-IdleWhenError -List $nodeErrors -Message ("{0}: NotEquals must be a hashtable with keys Left and Right." -f $opPath)
                    return $nodeErrors
                }

                foreach ($k in @($opVal.Keys)) {
                    if (@('Left', 'Right') -notcontains [string]$k) {
                        Add-IdleWhenError -List $nodeErrors -Message ("{0}: Unknown key '{1}'. Allowed: Left, Right." -f $opPath, [string]$k)
                    }
                }

                if (-not $opVal.Contains('Left') -or [string]::IsNullOrWhiteSpace([string]$opVal.Left)) {
                    Add-IdleWhenError -List $nodeErrors -Message ("{0}: Missing or empty Left." -f $opPath)
                }

                if (-not $opVal.Contains('Right')) {
                    Add-IdleWhenError -List $nodeErrors -Message ("{0}: Missing Right." -f $opPath)
                }

                return $nodeErrors
            }

            'Exists' {
                # Exists operator supports two forms:
                #   Exists = 'context.Attributes.mail'
                #   Exists = @{ Path = 'context.Attributes.mail' }
                if ($opVal -is [string]) {
                    if ([string]::IsNullOrWhiteSpace([string]$opVal)) {
                        Add-IdleWhenError -List $nodeErrors -Message ("{0}: Exists path must be a non-empty string." -f $opPath)
                    }
                    return $nodeErrors
                }

                if (-not ($opVal -is [System.Collections.IDictionary])) {
                    Add-IdleWhenError -List $nodeErrors -Message ("{0}: Exists must be a string path or a hashtable with key Path." -f $opPath)
                    return $nodeErrors
                }

                foreach ($k in @($opVal.Keys)) {
                    if (@('Path') -notcontains [string]$k) {
                        Add-IdleWhenError -List $nodeErrors -Message ("{0}: Unknown key '{1}'. Allowed: Path." -f $opPath, [string]$k)
                    }
                }

                if (-not $opVal.Contains('Path') -or [string]::IsNullOrWhiteSpace([string]$opVal.Path)) {
                    Add-IdleWhenError -List $nodeErrors -Message ("{0}: Missing or empty Path." -f $opPath)
                }

                return $nodeErrors
            }

            'In' {
                # In operator:
                #   In = @{ Left = 'context.Identity.Type'; Right = @('Joiner','Mover') }
                if (-not ($opVal -is [System.Collections.IDictionary])) {
                    Add-IdleWhenError -List $nodeErrors -Message ("{0}: In must be a hashtable with keys Left and Right." -f $opPath)
                    return $nodeErrors
                }

                foreach ($k in @($opVal.Keys)) {
                    if (@('Left', 'Right') -notcontains [string]$k) {
                        Add-IdleWhenError -List $nodeErrors -Message ("{0}: Unknown key '{1}'. Allowed: Left, Right." -f $opPath, [string]$k)
                    }
                }

                if (-not $opVal.Contains('Left') -or [string]::IsNullOrWhiteSpace([string]$opVal.Left)) {
                    Add-IdleWhenError -List $nodeErrors -Message ("{0}: Missing or empty Left." -f $opPath)
                }

                if (-not $opVal.Contains('Right')) {
                    Add-IdleWhenError -List $nodeErrors -Message ("{0}: Missing Right." -f $opPath)
                    return $nodeErrors
                }

                $right = $opVal.Right
                if ($null -eq $right) {
                    Add-IdleWhenError -List $nodeErrors -Message ("{0}: Right must not be null." -f $opPath)
                    return $nodeErrors
                }

                # Right should be a list/array (or scalar) but must not be a dictionary (ambiguous).
                if ($right -is [System.Collections.IDictionary]) {
                    Add-IdleWhenError -List $nodeErrors -Message ("{0}: Right must be a list/array (or scalar), not a dictionary." -f $opPath)
                }

                return $nodeErrors
            }
        }

        Add-IdleWhenError -List $nodeErrors -Message ("{0}: Unsupported operator '{1}'." -f $NodePath, $opKey)
        return $nodeErrors
    }

    # Validate recursively from root.
    foreach ($e in (Test-IdleConditionNodeSchema -Node $When -NodePath ("{0}: When" -f $prefix))) {
        Add-IdleWhenError -List $errors -Message $e
    }

    return $errors
}

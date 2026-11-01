Set-StrictMode -Version Latest

function Get-IdleConditionPaths {
    <#
    .SYNOPSIS
    Returns the paths referenced by a condition node, with the operator that uses them.

    .DESCRIPTION
    Walks All / Any / None groups and returns one entry per operator path. A leading 'context.' prefix
    is removed (as in Test-IdleCondition). Malformed nodes are ignored; Test-IdleConditionSchema reports them.

    .PARAMETER Condition
    Condition node (data-only hashtable).

    .OUTPUTS
    PSCustomObject[] with Operator and Path.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [System.Collections.IDictionary] $Condition
    )

    $result = [System.Collections.Generic.List[object]]::new()

    function Add-IdleConditionPath {
        param([string] $Operator, [object] $PathCandidate)

        if ($null -eq $PathCandidate) { return }

        $pathText = [string]$PathCandidate
        if ([string]::IsNullOrWhiteSpace($pathText)) { return }

        if ($pathText.StartsWith('context.', [System.StringComparison]::OrdinalIgnoreCase)) {
            $pathText = $pathText.Substring(8)
        }

        $result.Add([pscustomobject]@{ Operator = $Operator; Path = $pathText })
    }

    function Add-IdleConditionNodePaths {
        param([System.Collections.IDictionary] $Node)

        foreach ($group in @('All', 'Any', 'None')) {
            if ($Node.Contains($group)) {
                foreach ($child in @($Node[$group])) {
                    if ($child -is [System.Collections.IDictionary]) {
                        Add-IdleConditionNodePaths -Node $child
                    }
                }
                return
            }
        }

        if ($Node.Contains('Exists')) {
            $existsValue = $Node['Exists']
            if ($existsValue -is [System.Collections.IDictionary]) {
                Add-IdleConditionPath -Operator 'Exists' -PathCandidate $existsValue['Path']
            }
            else {
                Add-IdleConditionPath -Operator 'Exists' -PathCandidate $existsValue
            }
            return
        }

        foreach ($operator in @('Equals', 'NotEquals', 'In', 'Contains', 'NotContains', 'Like', 'NotLike')) {
            if ($Node.Contains($operator)) {
                $operatorNode = $Node[$operator]
                if ($operatorNode -is [System.Collections.IDictionary]) {
                    Add-IdleConditionPath -Operator $operator -PathCandidate $operatorNode['Path']
                }
                return
            }
        }
    }

    Add-IdleConditionNodePaths -Node $Condition

    # Enumerated to the pipeline; callers wrap the result in @().
    return $result.ToArray()
}

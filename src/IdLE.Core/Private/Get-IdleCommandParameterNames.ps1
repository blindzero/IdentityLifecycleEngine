Set-StrictMode -Version Latest

function Get-IdleCommandParameterNames {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Handler
    )

    # Returns a HashSet[string] of parameter names supported by the handler.
    $set = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    if ($Handler -is [scriptblock]) {

        $paramBlock = $Handler.Ast.ParamBlock
        if ($null -eq $paramBlock) {
            return $set
        }

        foreach ($p in $paramBlock.Parameters) {
            # Parameter name is stored without the leading '$'
            $null = $set.Add([string]$p.Name.VariablePath.UserPath)
        }

        return $set
    }

    if ($Handler -is [System.Management.Automation.CommandInfo]) {
        foreach ($n in $Handler.Parameters.Keys) {
            $null = $set.Add([string]$n)
        }
        return $set
    }

    # Unknown handler shape: return an empty set.
    return $set
}

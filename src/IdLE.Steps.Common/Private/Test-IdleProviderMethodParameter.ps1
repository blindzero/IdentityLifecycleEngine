# Tests whether a provider method supports a specific parameter.
# Used by steps to detect whether providers support optional AuthSession parameter.

function Test-IdleProviderMethodParameter {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $ProviderMethod,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $ParameterName
    )

    if ($ProviderMethod.MemberType -ne 'ScriptMethod') {
        return $false
    }

    $scriptBlock = $ProviderMethod.Script
    if ($null -eq $scriptBlock -or $null -eq $scriptBlock.Ast -or $null -eq $scriptBlock.Ast.ParamBlock) {
        return $false
    }

    $params = $scriptBlock.Ast.ParamBlock.Parameters
    if ($null -eq $params) {
        return $false
    }

    foreach ($param in $params) {
        if ($null -ne $param.Name -and $null -ne $param.Name.VariablePath) {
            $paramName = $param.Name.VariablePath.UserPath
            if ($paramName -eq $ParameterName) {
                return $true
            }
        }
    }

    return $false
}

# Tests whether a provider method supports a given parameter.
# Supports ScriptMethod (AST inspection) and compiled methods (reflection).

function Test-IdleProviderMethodParameter {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [System.Management.Automation.PSMethodInfo] $ProviderMethod,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $ParameterName
    )

    # For ScriptMethod, inspect the AST
    if ($ProviderMethod.MemberType -eq 'ScriptMethod') {
        $scriptBlock = $ProviderMethod.Script
        if ($null -ne $scriptBlock -and $null -ne $scriptBlock.Ast -and $null -ne $scriptBlock.Ast.ParamBlock) {
            $params = $scriptBlock.Ast.ParamBlock.Parameters
            if ($null -ne $params) {
                foreach ($param in $params) {
                    if ($null -ne $param.Name -and $null -ne $param.Name.VariablePath) {
                        $paramName = $param.Name.VariablePath.UserPath
                        if ($paramName -eq $ParameterName) {
                            return $true
                        }
                    }
                }
            }
        }
        return $false
    }

    # For compiled methods (PSMethod, CodeMethod), use reflection
    if ($ProviderMethod.MemberType -in @('Method', 'CodeMethod')) {
        try {
            # Get the method info via reflection
            $methodInfo = $ProviderMethod.OverloadDefinitions
            if ($null -ne $methodInfo) {
                # Check if any overload contains the parameter name
                foreach ($overload in $methodInfo) {
                    if ($overload -match "\b$ParameterName\b") {
                        return $true
                    }
                }
            }
        }
        catch {
            # If reflection fails, assume parameter is not supported
            Write-Verbose "Could not inspect compiled method parameters: $_"
        }
        return $false
    }

    # Unknown method type
    return $false
}

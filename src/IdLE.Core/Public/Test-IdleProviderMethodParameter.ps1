# Tests whether a provider method supports a given parameter.
# Supports ScriptMethod (AST inspection) and compiled methods (reflection).

function Test-IdleProviderMethodParameter {
    <#
    .SYNOPSIS
    Tests whether a provider method supports a given parameter.

    .DESCRIPTION
    This is a foundational helper that inspects provider method signatures to determine
    if they accept a specific parameter (e.g., AuthSession).

    Supports:
    - ScriptMethod (AST inspection via PowerShell parser)
    - Compiled methods (reflection-based inspection)

    Used by Invoke-IdleProviderMethod to detect backwards-compatible method signatures.

    .PARAMETER ProviderMethod
    PSMethodInfo object representing the provider method to inspect.

    .PARAMETER ParameterName
    Name of the parameter to check for (e.g., 'AuthSession').

    .OUTPUTS
    Boolean. True if the method accepts the specified parameter, False otherwise.

    .EXAMPLE
    $provider = [pscustomobject]@{}
    $provider | Add-Member -MemberType ScriptMethod -Name MyMethod -Value {
        param($Arg1, $AuthSession)
        # ...
    }

    $method = $provider.PSObject.Methods['MyMethod']
    Test-IdleProviderMethodParameter -ProviderMethod $method -ParameterName 'AuthSession'
    # Returns: True
    #>
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
        
        # Early exit if required objects are missing
        if ($null -eq $scriptBlock) { return $false }
        if ($null -eq $scriptBlock.Ast) { return $false }
        if ($null -eq $scriptBlock.Ast.ParamBlock) { return $false }
        
        $params = $scriptBlock.Ast.ParamBlock.Parameters
        if ($null -eq $params) { return $false }
        
        # Check each parameter for a match
        foreach ($param in $params) {
            if ($null -eq $param.Name) { continue }
            if ($null -eq $param.Name.VariablePath) { continue }
            
            $paramName = $param.Name.VariablePath.UserPath
            if ($paramName -eq $ParameterName) {
                return $true
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

# Invokes a provider method with optional AuthSession support.
# Handles auth session acquisition, parameter detection, and backwards-compatible fallback.

function Invoke-IdleProviderMethod {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Context,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable] $With,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $ProviderAlias,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $MethodName,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object[]] $MethodArguments
    )

    # Auth session acquisition (optional, data-only)
    $authSession = $null
    if ($With.ContainsKey('AuthSessionName')) {
        $sessionName = [string]$With.AuthSessionName
        $sessionOptions = if ($With.ContainsKey('AuthSessionOptions')) { $With.AuthSessionOptions } else { $null }

        if ($null -ne $sessionOptions -and -not ($sessionOptions -is [hashtable])) {
            throw "With.AuthSessionOptions must be a hashtable or null."
        }

        $authSession = $Context.AcquireAuthSession($sessionName, $sessionOptions)
    }

    $provider = $Context.Providers[$ProviderAlias]

    # Check if provider method exists
    $providerMethod = $provider.PSObject.Methods[$MethodName]
    if ($null -eq $providerMethod) {
        throw "Provider '$ProviderAlias' does not implement $MethodName method."
    }

    # Check if method supports AuthSession parameter
    $supportsAuthSession = $false
    if ($providerMethod.MemberType -eq 'ScriptMethod') {
        $scriptBlock = $providerMethod.Script
        if ($null -ne $scriptBlock -and $null -ne $scriptBlock.Ast -and $null -ne $scriptBlock.Ast.ParamBlock) {
            $params = $scriptBlock.Ast.ParamBlock.Parameters
            if ($null -ne $params) {
                foreach ($param in $params) {
                    if ($null -ne $param.Name -and $null -ne $param.Name.VariablePath) {
                        $paramName = $param.Name.VariablePath.UserPath
                        if ($paramName -eq 'AuthSession') {
                            $supportsAuthSession = $true
                            break
                        }
                    }
                }
            }
        }
    }

    # Call provider method with appropriate signature
    if ($supportsAuthSession -and $null -ne $authSession) {
        # Provider supports AuthSession and we have one - pass it
        $allArgs = $MethodArguments + $authSession
        return $provider.$MethodName.Invoke($allArgs)
    }
    else {
        # Legacy signature (no AuthSession parameter) or no session acquired
        return $provider.$MethodName.Invoke($MethodArguments)
    }
}

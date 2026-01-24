# Invokes a provider method with optional AuthSession support.
# Handles auth session acquisition, parameter detection, and backwards-compatible fallback.
#
# NOTE: This is a copy of the function from IdLE.Steps.Common/Private/Invoke-IdleProviderMethod.ps1
# The duplication is necessary because:
# 1. The function is Private in IdLE.Steps.Common and not exported
# 2. RequiredModules does not make Private functions available to dependent modules
# 3. Making it Public would expose implementation details that should remain internal
# This is the same pattern used by IdLE.Steps.DirectorySync which calls this function
# via the Common module's internal scope when RequiredModules is declared.

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
        [AllowEmptyCollection()]
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
    $supportsAuthSession = Test-IdleProviderMethodParameter -ProviderMethod $providerMethod -ParameterName 'AuthSession'

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

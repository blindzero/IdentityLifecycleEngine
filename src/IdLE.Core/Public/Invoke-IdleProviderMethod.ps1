# Invokes a provider method with optional AuthSession support.
# Handles auth session acquisition, parameter detection, and backwards-compatible fallback.

function Invoke-IdleProviderMethod {
    <#
    .SYNOPSIS
    Invokes a provider method with optional AuthSession support.

    .DESCRIPTION
    This is a foundational helper for step implementations that need to invoke
    provider methods with proper authentication handling.

    Key features:
    - Acquires auth sessions via Context.AcquireAuthSession when AuthSessionBroker is available
    - If With.AuthSessionName is present, uses it for session routing
    - If With.AuthSessionName is absent but broker exists, attempts to acquire default session
    - Detects whether provider methods support AuthSession parameter (backwards compatible)
    - Passes AuthSession to provider methods that support it
    - Validates provider existence and method implementation

    .PARAMETER Context
    Execution context created by IdLE.Core. Must contain Providers hashtable and
    AcquireAuthSession method.

    .PARAMETER With
    Step configuration hashtable. May contain:
    - AuthSessionName (string): Name of auth session to acquire
    - AuthSessionOptions (hashtable): Optional session selection options

    .PARAMETER ProviderAlias
    Key to look up the provider in Context.Providers.

    .PARAMETER MethodName
    Name of the provider method to invoke.

    .PARAMETER MethodArguments
    Array of arguments to pass to the provider method (excluding AuthSession).

    .OUTPUTS
    Object returned by the provider method.

    .EXAMPLE
    $result = Invoke-IdleProviderMethod `
        -Context $Context `
        -With @{ AuthSessionName = 'ExchangeOnline' } `
        -ProviderAlias 'ExchangeOnline' `
        -MethodName 'EnsureMailboxType' `
        -MethodArguments @('user@contoso.com', 'Shared')
    #>
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
    
    # Validate AuthSessionOptions early (regardless of broker availability)
    if ($With.ContainsKey('AuthSessionOptions')) {
        $sessionOptions = $With.AuthSessionOptions
        if ($null -ne $sessionOptions -and -not ($sessionOptions -is [hashtable])) {
            throw "With.AuthSessionOptions must be a hashtable or null."
        }
    }
    
    $provider = $Context.Providers[$ProviderAlias]

    # Check if provider method exists
    $providerMethod = $provider.PSObject.Methods[$MethodName]
    if ($null -eq $providerMethod) {
        throw "Provider '$ProviderAlias' does not implement $MethodName method."
    }

    # Check if method supports AuthSession parameter
    $supportsAuthSession = Test-IdleProviderMethodParameter -ProviderMethod $providerMethod -ParameterName 'AuthSession'
    
    # Check if context can acquire auth sessions
    $canAcquireAuth = $Context.PSObject.Methods.Name -contains 'AcquireAuthSession'
    
    # Only acquire auth session if provider method can use it or if explicitly requested
    $shouldAcquireAuth = $With.ContainsKey('AuthSessionName') -or ($supportsAuthSession -and $canAcquireAuth)
    
    if ($shouldAcquireAuth) {
        if (-not $canAcquireAuth) {
            # AuthSessionName was explicitly set but context cannot acquire sessions
            throw "With.AuthSessionName is set to '$($With.AuthSessionName)' but Context does not have an AcquireAuthSession method."
        }
        
        # If AuthSessionName is provided, use it for routing
        if ($With.ContainsKey('AuthSessionName')) {
            $sessionName = [string]$With.AuthSessionName
            $sessionOptions = if ($With.ContainsKey('AuthSessionOptions')) { $With.AuthSessionOptions } else { $null }

            $authSession = $Context.AcquireAuthSession($sessionName, $sessionOptions)
        }
        else {
            # No AuthSessionName provided but provider supports auth - try to acquire default session
            # Use empty string to signal default request without conflicting with user session names
            try {
                $authSession = $Context.AcquireAuthSession('', $null)
            }
            catch {
                # If provider method supports AuthSession and default acquisition fails, rethrow
                if ($supportsAuthSession) {
                    throw
                }
                # Otherwise, continue without auth session for backward compatibility
                $authSession = $null
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

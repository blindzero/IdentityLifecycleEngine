# Re-export authentication session broker functionality from IdLE.Core.
# This wrapper is necessary because PowerShell's Export-ModuleMember can only export
# functions defined in the current module's scope. The wrapper creates the function
# in IdLE's scope, allowing it to be exported.
#
# The function is named New-IdleAuthSession to provide a clean public API name,
# while the Core implementation remains as New-IdleAuthSessionBroker.

function New-IdleAuthSession {
    <#
    .SYNOPSIS
    Creates a simple AuthSessionBroker for use with IdLE providers.

    .DESCRIPTION
    Creates an AuthSessionBroker that routes authentication based on user-defined options.
    The broker is used by steps to acquire credentials at runtime without embedding
    secrets in workflows or provider construction.

    This is a thin wrapper that delegates to IdLE.Core\New-IdleAuthSessionBroker.

    .PARAMETER SessionMap
    A hashtable that maps session configurations to auth sessions.

    .PARAMETER DefaultAuthSession
    Optional default auth session to return when no session options are provided.

    .PARAMETER AuthSessionType
    Optional default authentication session type. Acts as the default for untyped
    SessionMap entries and DefaultAuthSession.

    Valid values:
    - 'OAuth': Token-based authentication (e.g., Microsoft Graph, Exchange Online)
    - 'PSRemoting': PowerShell remoting execution context (e.g., Entra Connect)
    - 'Credential': Credential-based authentication (e.g., Active Directory, mock providers)

    If not provided, all SessionMap values and DefaultAuthSession must be typed
    (include AuthSessionType and Session properties).

    .EXAMPLE
    $broker = New-IdleAuthSession -SessionMap @{
        @{ Role = 'Tier0' } = $tier0Credential
    } -AuthSessionType 'Credential'

    .OUTPUTS
    PSCustomObject with AcquireAuthSession method

    .NOTES
    For detailed documentation, see: Get-Help IdLE.Core\New-IdleAuthSessionBroker -Full
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [AllowEmptyCollection()]
        [hashtable] $SessionMap,

        [Parameter()]
        [AllowNull()]
        [object] $DefaultAuthSession,

        [Parameter()]
        [ValidateSet('OAuth', 'PSRemoting', 'Credential')]
        [string] $AuthSessionType
    )

    # Delegate to IdLE.Core implementation.
    $params = @{}
    if ($PSBoundParameters.ContainsKey('SessionMap')) {
        $params['SessionMap'] = $SessionMap
    }
    if ($PSBoundParameters.ContainsKey('DefaultAuthSession')) {
        $params['DefaultAuthSession'] = $DefaultAuthSession
    }
    if ($PSBoundParameters.ContainsKey('AuthSessionType')) {
        $params['AuthSessionType'] = $AuthSessionType
    }
    
    return IdLE.Core\New-IdleAuthSessionBroker @params
}


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
    A hashtable that maps session configurations to typed auth sessions.

    .PARAMETER DefaultAuthSession
    Optional default typed auth session to return when no session options are provided.

    .EXAMPLE
    # Simple broker with single credential
    $broker = New-IdleAuthSession -DefaultAuthSession @{
        AuthSessionType = 'Credential'
        Session = $credential
    }

    .EXAMPLE
    # Mixed-type broker for AD + EXO
    $broker = New-IdleAuthSession -SessionMap @{
        @{ AuthSessionName = 'AD' } = @{ AuthSessionType = 'Credential'; Session = $adCred }
        @{ AuthSessionName = 'EXO' } = @{ AuthSessionType = 'OAuth'; Session = $token }
    }

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
        [object] $DefaultAuthSession
    )

    # Delegate to IdLE.Core implementation.
    $params = @{}
    if ($PSBoundParameters.ContainsKey('SessionMap')) {
        $params['SessionMap'] = $SessionMap
    }
    if ($PSBoundParameters.ContainsKey('DefaultAuthSession')) {
        $params['DefaultAuthSession'] = $DefaultAuthSession
    }
    
    return IdLE.Core\New-IdleAuthSessionBroker @params
}


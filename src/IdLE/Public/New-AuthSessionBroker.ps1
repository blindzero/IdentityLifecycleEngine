# Re-export New-IdleAuthSessionBroker from IdLE.Core.
# This avoids filename collision while keeping the wrapper minimal.

function New-IdleAuthSessionBroker {
    <#
    .SYNOPSIS
    Creates a simple AuthSessionBroker for use with IdLE providers.

    .DESCRIPTION
    Creates an AuthSessionBroker that routes authentication based on user-defined options.
    The broker is used by steps to acquire credentials at runtime without embedding
    secrets in workflows or provider construction.

    This is a thin wrapper that delegates to IdLE.Core\New-IdleAuthSessionBroker.

    .PARAMETER SessionMap
    A hashtable that maps session configurations to credentials.

    .PARAMETER DefaultCredential
    Optional default credential to return when no session options are provided.

    .EXAMPLE
    $broker = New-IdleAuthSessionBroker -SessionMap @{
        @{ Role = 'Tier0' } = $tier0Credential
    }

    .OUTPUTS
    PSCustomObject with AcquireAuthSession method

    .NOTES
    For detailed documentation, see: Get-Help IdLE.Core\New-IdleAuthSessionBroker -Full
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable] $SessionMap,

        [Parameter()]
        [AllowNull()]
        [PSCredential] $DefaultCredential
    )

    # Delegate to IdLE.Core implementation.
    $params = @{ SessionMap = $SessionMap }
    if ($PSBoundParameters.ContainsKey('DefaultCredential')) {
        $params['DefaultCredential'] = $DefaultCredential
    }
    
    return IdLE.Core\New-IdleAuthSessionBroker @params
}

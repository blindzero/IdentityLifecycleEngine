function New-IdleAuthSessionBroker {
    <#
    .SYNOPSIS
    Creates a simple AuthSessionBroker for use with IdLE providers.

    .DESCRIPTION
    Creates an AuthSessionBroker that routes authentication based on user-defined options.
    The broker is used by steps to acquire credentials at runtime without embedding
    secrets in workflows or provider construction.

    This is a convenience function for common scenarios. For advanced scenarios
    (vault integration, MFA, etc.), implement a custom broker object with an
    AcquireAuthSession method.

    .PARAMETER SessionMap
    A hashtable that maps session configurations to credentials. Each key is a hashtable
    representing the AuthSessionOptions pattern, and each value is the PSCredential to return.

    Common patterns:
    - @{ Role = 'Tier0' } -> $tier0Credential
    - @{ Role = 'Admin' } -> $adminCredential
    - @{ Domain = 'SourceAD' } -> $sourceCred
    - @{ Environment = 'Production' } -> $prodCred

    .PARAMETER DefaultCredential
    Optional default credential to return when no session options are provided or
    when the options don't match any entry in SessionMap.

    .EXAMPLE
    # Simple role-based broker
    $broker = New-IdleAuthSessionBroker -SessionMap @{
        @{ Role = 'Tier0' } = $tier0Credential
        @{ Role = 'Admin' } = $adminCredential
    } -DefaultCredential $adminCredential

    $plan = New-IdlePlan -WorkflowPath './workflow.psd1' -Request $request -Providers @{
        Identity = New-IdleADIdentityProvider
        AuthSessionBroker = $broker
    }

    .EXAMPLE
    # Domain-based broker for multi-forest scenarios
    $broker = New-IdleAuthSessionBroker -SessionMap @{
        @{ Domain = 'SourceAD' } = $sourceCred
        @{ Domain = 'TargetAD' } = $targetCred
    }

    .OUTPUTS
    PSCustomObject with AcquireAuthSession method
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

    # Keep meta module thin: delegate to IdLE.Core.
    # Since IdLE.Core is a nested module, its exported functions are available in the current scope.
    if ($PSBoundParameters.ContainsKey('DefaultCredential')) {
        return IdLE.Core\New-IdleAuthSessionBroker -SessionMap $SessionMap -DefaultCredential $DefaultCredential
    }
    else {
        return IdLE.Core\New-IdleAuthSessionBroker -SessionMap $SessionMap
    }
}

function Invoke-IdleStepEnsureEntitlement {
    <#
    .SYNOPSIS
    Ensures that an entitlement assignment is present or absent for an identity.

    .DESCRIPTION
    This provider-agnostic step uses entitlement provider contracts to converge
    an assignment to the desired state. The engine passes the provider resolved from With.Provider (default 'Identity')
    as -Provider. The provider implements:

    - ListEntitlements(identityKey)
    - GrantEntitlement(identityKey, entitlement)
    - RevokeEntitlement(identityKey, entitlement)

    The step is idempotent and only calls Grant/Revoke when the assignment needs
    to change.

    Authentication is handled by the engine (With.AuthSessionName, With.AuthSessionOptions).

    .PARAMETER With
    Validated With hashtable: IdentityKey, Entitlement (@{ Kind; Id; DisplayName }), State ('Present' or 'Absent').

    .PARAMETER Provider
    Provider handle created by the engine (see docs/extend/steps.md).

    .EXAMPLE
    @{
        Name = 'Ensure group access'
        Type = 'IdLE.Step.EnsureEntitlement'
        With = @{
            IdentityKey = 'user1'
            Entitlement = @{ Kind = 'Group'; Id = 'example-group' }
            State       = 'Present'
        }
    }

    .OUTPUTS
    System.Collections.Hashtable (Changed)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable] $With,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Provider
    )

    function Test-IdleStepEntitlementEquals {
        param([object] $A, [object] $B)

        $kindA = if ($A -is [System.Collections.IDictionary]) { $A['Kind'] } else { $A.Kind }
        $idA = if ($A -is [System.Collections.IDictionary]) { $A['Id'] } else { $A.Id }

        if (-not [string]::Equals([string]$kindA, [string]$B.Kind, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $false
        }

        return [string]::Equals([string]$idA, [string]$B.Id, [System.StringComparison]::OrdinalIgnoreCase)
    }

    $identityKey = [string]$With.IdentityKey
    $entitlement = [pscustomobject]@{
        Kind = [string]$With.Entitlement.Kind
        Id   = [string]$With.Entitlement.Id
    }

    # Pass Kind to the provider when supported, so it can skip fetching unrelated objects
    # (e.g. avoid AU Graph calls for a Group entitlement check).
    $listArguments = if ($Provider.HasParameter('ListEntitlements', 'Kind')) { @($identityKey, $entitlement.Kind) } else { @($identityKey) }
    $current = @($Provider.Invoke('ListEntitlements', $listArguments))
    $isAssigned = @($current | Where-Object { Test-IdleStepEntitlementEquals -A $_ -B $entitlement }).Count -gt 0

    $method = $null
    if ($With.State -eq 'Present' -and -not $isAssigned) { $method = 'GrantEntitlement' }
    if ($With.State -eq 'Absent' -and $isAssigned) { $method = 'RevokeEntitlement' }

    if ($null -eq $method) {
        return @{ Changed = $false }
    }

    $result = $Provider.Invoke($method, @($identityKey, $entitlement))

    # Providers without a result object are assumed to have changed the assignment.
    $changed = if ($null -ne $result -and ($result.PSObject.Properties.Name -contains 'Changed')) { [bool]$result.Changed } else { $true }
    return @{ Changed = $changed }
}

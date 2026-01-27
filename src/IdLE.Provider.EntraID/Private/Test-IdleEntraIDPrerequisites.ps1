Set-StrictMode -Version Latest

function Test-IdleEntraIDPrerequisites {
    <#
    .SYNOPSIS
    Checks if the Microsoft Entra ID prerequisites are available.

    .DESCRIPTION
    Validates prerequisites for the Entra ID provider. The default adapter uses
    Invoke-RestMethod (built into PowerShell) to call Microsoft Graph API, so there
    are no external module dependencies for the adapter itself.

    However, the host must provide valid Graph API authentication (access tokens)
    via the AuthSessionBroker pattern for operations to succeed.

    This function does not throw and returns a structured result object
    that can be used by the provider to emit warnings or by provider methods
    to validate operational readiness.

    .OUTPUTS
    PSCustomObject with PSTypeName 'IdLE.PrerequisitesResult'
    - PSTypeName: 'IdLE.PrerequisitesResult'
    - ProviderName: 'EntraIDIdentityProvider'
    - IsHealthy: $true if all required prerequisites are met
    - MissingRequired: array of missing required modules/components
    - MissingOptional: array of missing optional modules/components
    - Notes: array of additional notes or recommendations
    - CheckedAt: datetime when the check was performed

    .EXAMPLE
    $prereqs = Test-IdleEntraIDPrerequisites
    if (-not $prereqs.IsHealthy) {
        Write-Warning "EntraID prerequisites check failed: $($prereqs.MissingRequired -join ', ')"
    }
    #>
    [CmdletBinding()]
    param()

    $missingRequired = @()
    $missingOptional = @()
    $notes = @()

    # The default Entra ID adapter uses Invoke-RestMethod (built-in) to call Graph API.
    # No external module dependencies are required by the adapter itself.
    # 
    # Authentication is provided by the host via AuthSessionBroker pattern at runtime.
    # If auth fails at runtime, the Graph API calls will fail with actionable errors.

    # Check if Invoke-RestMethod is available (should always be available in PS 7+)
    if (-not (Get-Command -Name 'Invoke-RestMethod' -ErrorAction SilentlyContinue)) {
        $missingRequired += 'Invoke-RestMethod'
        $notes += 'Invoke-RestMethod cmdlet is required but not available in this PowerShell session.'
    }

    $isHealthy = ($missingRequired.Count -eq 0)

    if (-not $isHealthy) {
        $notes += 'The Entra ID provider requires valid Graph API authentication at runtime via AuthSessionBroker.'
        $notes += 'Ensure the host provides access tokens with required permissions: User.Read.All, User.ReadWrite.All, Group.Read.All, GroupMember.ReadWrite.All'
    }

    return [pscustomobject]@{
        PSTypeName       = 'IdLE.PrerequisitesResult'
        ProviderName     = 'EntraIDIdentityProvider'
        IsHealthy        = $isHealthy
        MissingRequired  = $missingRequired
        MissingOptional  = $missingOptional
        Notes            = $notes
        CheckedAt        = [datetime]::UtcNow
    }
}

function Test-IdleExchangeOnlinePrerequisites {
    <#
    .SYNOPSIS
    Checks if the Exchange Online prerequisites are available.

    .DESCRIPTION
    Validates that the ExchangeOnlineManagement PowerShell module is available.
    This module is required for all Exchange Online provider operations.

    This function does not throw and returns a structured result object
    that can be used by the provider to emit warnings or by provider methods
    to throw actionable errors when prerequisites are missing.

    .OUTPUTS
    PSCustomObject with PSTypeName 'IdLE.PrerequisitesResult'
    - PSTypeName: 'IdLE.PrerequisitesResult'
    - ProviderName: 'ExchangeOnlineProvider'
    - IsHealthy: $true if all required prerequisites are met
    - MissingRequired: array of missing required modules/components
    - MissingOptional: array of missing optional modules/components
    - Notes: array of additional notes or recommendations
    - CheckedAt: datetime when the check was performed

    .EXAMPLE
    $prereqs = Test-IdleExchangeOnlinePrerequisites
    if (-not $prereqs.IsHealthy) {
        Write-Warning "ExchangeOnline prerequisites check failed: $($prereqs.MissingRequired -join ', ')"
    }
    #>
    [CmdletBinding()]
    param()

    $missingRequired = @()
    $missingOptional = @()
    $notes = @()

    # Check for ExchangeOnlineManagement module (required)
    $exoModule = Get-Module -Name 'ExchangeOnlineManagement' -ListAvailable -ErrorAction SilentlyContinue
    if ($null -eq $exoModule) {
        $missingRequired += 'ExchangeOnlineManagement'
        $notes += 'The ExchangeOnlineManagement PowerShell module is required for all Exchange Online provider operations.'
        $notes += 'Install via: Install-Module -Name ExchangeOnlineManagement -Scope CurrentUser'
    }

    $isHealthy = ($missingRequired.Count -eq 0)

    return [pscustomobject]@{
        PSTypeName       = 'IdLE.PrerequisitesResult'
        ProviderName     = 'ExchangeOnlineProvider'
        IsHealthy        = $isHealthy
        MissingRequired  = $missingRequired
        MissingOptional  = $missingOptional
        Notes            = $notes
        CheckedAt        = [datetime]::UtcNow
    }
}

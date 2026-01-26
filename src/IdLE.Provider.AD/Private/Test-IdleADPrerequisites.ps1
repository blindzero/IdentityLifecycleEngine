function Test-IdleADPrerequisites {
    <#
    .SYNOPSIS
    Checks if the Active Directory prerequisites are available.

    .DESCRIPTION
    Validates that the ActiveDirectory PowerShell module (RSAT) is available.
    This module is required for all AD provider operations.

    This function does not throw and returns a structured result object
    that can be used by the provider to emit warnings or by provider methods
    to throw actionable errors when prerequisites are missing.

    .OUTPUTS
    PSCustomObject with PSTypeName 'IdLE.PrerequisitesResult'
    - PSTypeName: 'IdLE.PrerequisitesResult'
    - ProviderName: 'ADIdentityProvider'
    - IsHealthy: $true if all required prerequisites are met
    - MissingRequired: array of missing required modules/components
    - MissingOptional: array of missing optional modules/components
    - Notes: array of additional notes or recommendations
    - CheckedAt: datetime when the check was performed

    .EXAMPLE
    $prereqs = Test-IdleADPrerequisites
    if (-not $prereqs.IsHealthy) {
        Write-Warning "AD prerequisites check failed: $($prereqs.MissingRequired -join ', ')"
    }
    #>
    [CmdletBinding()]
    param()

    $missingRequired = @()
    $missingOptional = @()
    $notes = @()

    # Check for ActiveDirectory module (required)
    $adModule = Get-Module -Name 'ActiveDirectory' -ListAvailable -ErrorAction SilentlyContinue
    if ($null -eq $adModule) {
        $missingRequired += 'ActiveDirectory'
        $notes += 'The ActiveDirectory PowerShell module (RSAT-AD-PowerShell) is required for all AD provider operations.'
        $notes += 'Install via: Add-WindowsCapability -Online -Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0'
    }

    $isHealthy = ($missingRequired.Count -eq 0)

    return [pscustomobject]@{
        PSTypeName       = 'IdLE.PrerequisitesResult'
        ProviderName     = 'ADIdentityProvider'
        IsHealthy        = $isHealthy
        MissingRequired  = $missingRequired
        MissingOptional  = $missingOptional
        Notes            = $notes
        CheckedAt        = [datetime]::UtcNow
    }
}

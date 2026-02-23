Set-StrictMode -Version Latest

function Test-IdleExchangeOnlinePrerequisites {
    <#
    .SYNOPSIS
    Checks if the Exchange Online prerequisites are available.

    .DESCRIPTION
    Validates that the ExchangeOnlineManagement PowerShell module is available and that
    a working Exchange Online session exists in the current runspace.

    Three checks are performed in order:
    1. Module availability  — ExchangeOnlineManagement must be installed.
    2. Module import        — Get-EXOMailbox must be discoverable (module imported in session).
    3. Session established  — Set-Mailbox must be available (Connect-ExchangeOnline was called).

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
    else {
        # Module is available — now verify key cmdlets are accessible.
        # Get-EXOMailbox is a native module cmdlet (always present after Import-Module).
        # Its absence means the module has not been imported into this session yet.
        $exoMailboxCmd = Get-Command -Name 'Get-EXOMailbox' -ErrorAction SilentlyContinue
        if ($null -eq $exoMailboxCmd) {
            $missingRequired += 'Get-EXOMailbox'
            $notes += "The ExchangeOnlineManagement module is installed but 'Get-EXOMailbox' is not available in this session."
            $notes += 'Ensure the module is imported: Import-Module ExchangeOnlineManagement'
        }

        # Set-Mailbox is a session proxy cmdlet — only available after Connect-ExchangeOnline.
        # Its absence means no active Exchange Online session exists in this runspace.
        $setMailboxCmd = Get-Command -Name 'Set-Mailbox' -ErrorAction SilentlyContinue
        if ($null -eq $setMailboxCmd) {
            $missingRequired += 'ExchangeOnlineSession'
            $notes += "No active Exchange Online session detected ('Set-Mailbox' is not available)."
            $notes += 'Establish a session before using the provider: Connect-ExchangeOnline -UserPrincipalName admin@contoso.com'
            $notes += "For delegated access, acquire a token scoped to 'https://outlook.office365.com/.default' and pass it via -AccessToken."
        }
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

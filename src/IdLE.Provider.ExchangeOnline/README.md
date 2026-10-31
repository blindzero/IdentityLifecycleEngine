# IdLE.Provider.ExchangeOnline

Exchange Online mailbox provider for IdLE.

## Quick Start

```powershell
# Import IdLE (includes the Exchange Online provider)
Import-Module IdLE

# Host establishes Exchange Online session (delegated or app-only)
Connect-ExchangeOnline -UserPrincipalName admin@contoso.com

# Create provider
$provider = New-IdleExchangeOnlineProvider

# Use in workflows
$providers = @{
    ExchangeOnline = $provider
}
$plan = New-IdlePlan -WorkflowPath '.\leaver.psd1' -Request $request -Providers $providers
```

## Prerequisites

- PowerShell 7.0+
- ExchangeOnlineManagement module (`Install-Module ExchangeOnlineManagement`)
- Authenticated Exchange Online session (host-managed)
- **App-only auth**: Windows only (MVP)

## Documentation

See the main IdLE documentation for:
- Full usage guide and examples
- Capabilities and mailbox steps
- Authentication patterns (delegated + app-only)
- Required permissions
- Troubleshooting

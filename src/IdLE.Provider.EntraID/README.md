# IdLE.Provider.EntraID

Microsoft Entra ID (Azure AD) provider for IdLE.

## Quick Start

```powershell
# Automatically imported when you import IdLE
Import-Module IdLE

# Host obtains Graph access token (delegated or app-only)
$token = Get-GraphToken

# Create broker for auth routing
$broker = New-IdleAuthSessionBroker -SessionMap @{
    @{} = $token
} -DefaultCredential $token

# Create provider
$provider = New-IdleEntraIDIdentityProvider

# Use in workflows
$providers = @{
    Identity = $provider
    AuthSessionBroker = $broker
}
$plan = New-IdlePlan -WorkflowPath '.\joiner.psd1' -Request $request -Providers $providers
```

## Prerequisites

- PowerShell 7.0+
- Microsoft Graph API access token (host-managed)

## Documentation

See **[Complete Provider Documentation](../../docs/reference/providers/provider-entraID.md)** for:
- Full usage guide and examples
- Capabilities and built-in steps
- Authentication patterns (delegated + app-only)
- Required Graph API permissions
- Identity resolution and idempotency
- Troubleshooting

# IdLE.Provider.AD

Active Directory (on-premises) provider for IdLE.

## Quick Start

```powershell
# Automatically imported when you import IdLE
Import-Module IdLE

# Create provider
$provider = New-IdleADIdentityProvider

# Use in workflows
$providers = @{ Identity = $provider }
$plan = New-IdlePlan -WorkflowPath '.\joiner.psd1' -Request $request -Providers $providers
```

## Prerequisites

- **Windows only** (requires RSAT/ActiveDirectory module)
- PowerShell 7.0+

## Documentation

See **[Complete Provider Documentation](../../docs/reference/providers/provider-ad.md)** for:

- Full usage guide and examples
- Capabilities and built-in steps
- Identity resolution and idempotency
- Prerequisites and permissions
- Troubleshooting

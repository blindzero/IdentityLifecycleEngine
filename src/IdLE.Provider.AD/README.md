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

## Key Features

### Automatic Password Generation

When creating enabled AD accounts without specifying a password, the provider automatically generates policy-compliant passwords:

- Reads domain password policy via `Get-ADDefaultDomainPasswordPolicy`
- Falls back to configurable requirements if policy cannot be read
- Supports controlled plaintext output (opt-in) and secure reveal path

```powershell
# Default: password generated and returned as ProtectedString
$result = $provider.CreateIdentity('user@contoso.com', @{
    SamAccountName = 'jdoe'
    GivenName = 'John'
    Surname = 'Doe'
    Enabled = $true
})

# Access the protected password (DPAPI-scoped)
$protectedPwd = $result.GeneratedAccountPasswordProtected

# Reveal when needed:
$securePwd = ConvertTo-SecureString -String $protectedPwd
$plainPwd = [pscredential]::new('x', $securePwd).GetNetworkCredential().Password
```

See [Password Generation Documentation](../../docs/reference/providers/provider-ad.md#password-generation) for details.

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

# IdLE.Provider.AD

Active Directory (on-premises) provider for IdLE - enabling identity lifecycle automation with built-in Joiner/Mover/Leaver workflows.

## Quick Start

```powershell
# Module is automatically imported when you import IdLE
Import-Module IdLE

# Create provider instance
$provider = New-IdleADIdentityProvider

# Use with workflows
$providers = @{ Identity = $provider }
$plan = New-IdlePlan -WorkflowPath '.\joiner.psd1' -Request $request -Providers $providers
$result = Invoke-IdlePlan -Plan $plan -Providers $providers
```

## Platform Support

- **Windows only** (requires RSAT/ActiveDirectory module)
- PowerShell 7.0+
- Non-blocking import (loads even without RSAT - validation happens at provider instantiation)

## Key Features

- **Complete identity lifecycle operations**: Create, Read, Update, Delete (opt-in), Disable, Enable, Move
- **Group management**: List, Grant, Revoke group memberships
- **Flexible identity resolution**: GUID, UPN, sAMAccountName
- **Idempotent operations**: Safe for retries and re-runs
- **Built-in steps**: CreateIdentity, DisableIdentity, EnableIdentity, MoveIdentity, DeleteIdentity
- **Provider aliases**: Flexible naming for multi-provider scenarios

## Installation & Prerequisites

### Windows RSAT

**Windows Server:**
```powershell
Install-WindowsFeature -Name RSAT-AD-PowerShell
```

**Windows 10/11:**
```powershell
Get-WindowsCapability -Online -Name "Rsat.ActiveDirectory*" | Add-WindowsCapability -Online
```

### Active Directory Permissions

Grant only the minimum permissions required for your workflows. See the [full documentation](../../docs/reference/provider-ad.md#prerequisites) for detailed permission requirements.

## Basic Usage

### With Credentials

```powershell
$cred = Get-Credential
$provider = New-IdleADIdentityProvider -Credential $cred
```

### Enable Delete Operations (Opt-in)

```powershell
$provider = New-IdleADIdentityProvider -AllowDelete
```

### Multiple Providers

```powershell
$sourceAD = New-IdleADIdentityProvider -Credential $sourceCredential
$targetAD = New-IdleADIdentityProvider -Credential $targetCredential

$providers = @{
    SourceAD = $sourceAD
    TargetAD = $targetAD
}
# Reference in workflows: With = @{ Provider = 'SourceAD' }
```

## Capabilities

- `IdLE.Identity.Read`, `IdLE.Identity.List`, `IdLE.Identity.Create`, `IdLE.Identity.Delete` (opt-in)
- `IdLE.Identity.Disable`, `IdLE.Identity.Enable`, `IdLE.Identity.Move`
- `IdLE.Identity.Attribute.Ensure`
- `IdLE.Entitlement.List`, `IdLE.Entitlement.Grant`, `IdLE.Entitlement.Revoke`

**Note:** AD only supports `Kind='Group'` for entitlements (platform limitation).

## Example Workflows

See `examples/workflows/`:
- `ad-joiner-complete.psd1` - Complete onboarding
- `ad-mover-department-change.psd1` - Department change
- `ad-leaver-offboarding.psd1` - Offboarding with optional deletion

## Documentation

For comprehensive documentation including:
- Detailed capability descriptions
- Identity resolution rules
- Idempotency guarantees
- Built-in steps reference
- Troubleshooting guide
- Architecture notes

See **[Complete Provider Documentation](../../docs/reference/provider-ad.md)**

## Testing

```powershell
Invoke-Pester -Path .\tests\Providers\ADIdentityProvider.Tests.ps1
```

Tests use a fake adapter and don't require real Active Directory.

## License

See the main repository [LICENSE.md](../../LICENSE.md).

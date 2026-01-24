# IdLE.Provider.ExchangeOnline

Exchange Online mailbox provider for **IdentityLifecycleEngine (IdLE)**.

## Overview

This provider integrates IdLE with **Microsoft Exchange Online** for mailbox lifecycle management operations, including:

- Mailbox reporting (type, configuration, status)
- Mailbox type conversions (User ↔ Shared, Room, Equipment)
- Out of Office (OOF) configuration management

The provider implements the **mailbox-specific provider contract** used by the `IdLE.Steps.Mailbox` step pack.

## Prerequisites

- PowerShell 7.0 or later
- **ExchangeOnlineManagement** PowerShell module: `Install-Module -Name ExchangeOnlineManagement -Scope CurrentUser`
- Exchange Online subscription (Microsoft 365 / Office 365)
- Appropriate permissions:
  - **Delegated**: Exchange Administrator or Global Administrator role
  - **App-only**: Application permissions with `Exchange.ManageAsApp` (certificate-based, Windows only for MVP)

## Authentication

The provider uses the **AuthSessionBroker** pattern for runtime credential selection.

### Delegated (Interactive) Auth

```powershell
# Host establishes connection
Connect-ExchangeOnline -UserPrincipalName admin@contoso.com

# Create provider
$provider = New-IdleExchangeOnlineProvider

# Use in plan
$plan = New-IdlePlan -WorkflowPath './workflow.psd1' -Request $request -Providers @{
    ExchangeOnline = $provider
}
```

### App-Only (Certificate) Auth (Windows Only)

```powershell
# Host establishes connection with certificate
Connect-ExchangeOnline `
    -CertificateThumbprint $thumbprint `
    -AppId $appId `
    -Organization $tenantId

# Create provider
$provider = New-IdleExchangeOnlineProvider

# Use in plan
$plan = New-IdlePlan -WorkflowPath './workflow.psd1' -Request $request -Providers @{
    ExchangeOnline = $provider
}
```

> **Note**: App-only auth is Windows-only for MVP. Cross-platform support is planned for future releases.

## Capabilities

The provider advertises the following capabilities:

- `IdLE.Mailbox.Read` - Read mailbox details
- `IdLE.Mailbox.Type.Ensure` - Convert mailbox type (User/Shared/Room/Equipment)
- `IdLE.Mailbox.OutOfOffice.Ensure` - Configure Out of Office settings

## Identity Addressing

The provider supports:

- **UserPrincipalName (UPN)** - `john.doe@contoso.com` (preferred)
- **Primary SMTP address** - `john.doe@contoso.com`
- **Mailbox GUID** - `12345678-1234-1234-1234-123456789abc` (most deterministic)

The canonical identity key for all outputs is the **primary SMTP address**.

## Provider Contract Methods

### GetMailbox

Retrieve mailbox details.

```powershell
$mailbox = $provider.GetMailbox($identityKey, $authSession)
# Returns: PSCustomObject with PSTypeName = 'IdLE.Mailbox'
```

### EnsureMailboxType

Idempotent mailbox type conversion.

```powershell
$result = $provider.EnsureMailboxType($identityKey, 'Shared', $authSession)
# Returns: IdLE.ProviderResult with Changed flag
```

### GetOutOfOffice

Retrieve Out of Office configuration.

```powershell
$oofConfig = $provider.GetOutOfOffice($identityKey, $authSession)
# Returns: PSCustomObject with PSTypeName = 'IdLE.MailboxOutOfOffice'
```

### EnsureOutOfOffice

Idempotent Out of Office configuration.

```powershell
$config = @{
    Mode            = 'Enabled'
    InternalMessage = 'I am out of office.'
    ExternalMessage = 'I am currently unavailable.'
    ExternalAudience = 'All'
}
$result = $provider.EnsureOutOfOffice($identityKey, $config, $authSession)
# Returns: IdLE.ProviderResult with Changed flag
```

## See Also

- [IdLE.Steps.Mailbox](../IdLE.Steps.Mailbox/README.md) - Provider-agnostic mailbox step pack
- [Provider Documentation](../../docs/reference/providers/provider-exchangeonline.md)
- [Capability Documentation](../../docs/advanced/provider-capabilities.md)
- [ExchangeOnlineManagement Module](https://learn.microsoft.com/en-us/powershell/exchange/exchange-online-powershell)

## License

Apache License 2.0 - see [LICENSE.md](../../LICENSE.md)

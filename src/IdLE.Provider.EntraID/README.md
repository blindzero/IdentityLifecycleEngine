# IdLE.Provider.EntraID

Microsoft Entra ID (Azure AD) identity provider for IdentityLifecycleEngine (IdLE).

## Overview

This provider integrates with Microsoft Entra ID (formerly Azure Active Directory) via the Microsoft Graph API to support identity lifecycle operations.

## Features

- Identity operations: Create, Read, Enable, Disable, Delete (opt-in), Attribute management
- Group entitlement management: List, Grant, Revoke
- Multiple identity lookup modes: objectId (GUID), UserPrincipalName, mail
- Canonical identity key: objectId (GUID)
- Host-owned authentication via AuthSessionBroker pattern
- Idempotent operations for safe retries
- Transient error classification for retry policies
- Graph API paging support

## Requirements

- PowerShell 7.0+
- Microsoft Graph API access (v1.0 endpoints)
- Valid authentication session (delegated or app-only via host-provided AuthSessionBroker)

## Authentication

This provider does NOT perform authentication internally. Authentication is managed by the host via the `AuthSessionBroker` pattern as defined in IdLE architecture.

The provider expects to receive an authentication session from the host that provides a valid Microsoft Graph access token.

For details on required permissions and authentication setup, see [docs/reference/provider-entraID.md](../../docs/reference/provider-entraID.md).

## Usage

```powershell
# Basic usage with delegated auth
$broker = New-IdleAuthSessionBroker -SessionMap @{
    @{} = $graphAccessToken  # or PSCredential/object with AccessToken
} -DefaultCredential $graphAccessToken

$provider = New-IdleEntraIDIdentityProvider
$plan = New-IdlePlan -WorkflowPath './workflow.psd1' -Request $request -Providers @{
    Identity = $provider
    AuthSessionBroker = $broker
}
```

## Safety

The Delete capability is opt-in only for safety. Use `-AllowDelete` to enable:

```powershell
$provider = New-IdleEntraIDIdentityProvider -AllowDelete
```

## Documentation

- [Provider Reference](../../docs/reference/provider-entraID.md)
- [IdLE Architecture](../../docs/advanced/architecture.md)
- [Example Workflows](../../examples/workflows/)

## License

Apache 2.0

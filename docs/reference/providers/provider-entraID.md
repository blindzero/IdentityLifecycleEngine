---
title: Provider Reference - IdLE.Provider.EntraID
sidebar_label: Entra ID
---

Microsoft Entra ID (formerly Azure Active Directory) identity provider for IdLE.

## Overview

The `IdLE.Provider.EntraID` module provides a production-ready provider for managing identities and group entitlements in Microsoft Entra ID via the Microsoft Graph API (v1.0).

## Installation

The provider is included in the IdLE repository under `src/IdLE.Provider.EntraID/`.

```powershell
Import-Module ./src/IdLE.Provider.EntraID/IdLE.Provider.EntraID.psd1
```

## Authentication

### Host-Owned Authentication (Required Pattern)

The EntraID provider follows IdLE's **host-owned authentication** pattern. The provider does NOT perform authentication internally. Instead, authentication is managed by the host application via the `AuthSessionBroker`.

### What the Host Must Provide

The host must:

1. Obtain a valid Microsoft Graph access token (delegated or app-only)
2. Create an `AuthSessionBroker` that returns the token when requested
3. Pass the broker to IdLE via `Providers.AuthSessionBroker`

### Supported Auth Session Formats

The provider accepts authentication sessions in these formats:

- **String**: Direct access token (`"eyJ0eXAiOiJKV1Qi..."`)
- **Object with AccessToken property**: `@{ AccessToken = "token" }`
- **Object with GetAccessToken() method**: Custom object with method returning token string
- **PSCredential**: Token in password field (legacy compatibility)

### Example: Delegated Authentication

```powershell
# Host obtains token (example using Azure PowerShell)
Connect-AzAccount
$token = (Get-AzAccessToken -ResourceUrl "https://graph.microsoft.com").Token

# Create broker with OAuth session type (tokens can be passed directly)
$broker = New-IdleAuthSession -SessionMap @{
    @{} = $token
} -DefaultAuthSession $token -AuthSessionType 'OAuth'

# Create provider
$provider = New-IdleEntraIDIdentityProvider

# Use in plan
$plan = New-IdlePlan -WorkflowPath './workflow.psd1' -Request $request -Providers @{
    Identity = $provider
    AuthSessionBroker = $broker
}
```

### Example: App-Only Authentication (Service Principal)

```powershell
# Host obtains app-only token (example using MSAL or Azure PowerShell)
$clientId = "your-app-id"
$clientSecret = "your-secret"
$tenantId = "your-tenant-id"

# Obtain token (pseudo-code - use your preferred auth library)
$token = Get-GraphAppOnlyToken -ClientId $clientId -ClientSecret $clientSecret -TenantId $tenantId

# Create broker with OAuth session type (tokens can be passed directly)
$broker = New-IdleAuthSession -SessionMap @{
    @{} = $token
} -DefaultAuthSession $token -AuthSessionType 'OAuth'

# Rest is identical to delegated flow
```

### Example: Multi-Role Scenario

```powershell
$tier0Token = Get-GraphToken -Role 'Tier0'
$adminToken = Get-GraphToken -Role 'Admin'

# Create broker with OAuth session type (tokens can be passed directly)
$broker = New-IdleAuthSession -SessionMap @{
    @{ Role = 'Tier0' } = $tier0Token
    @{ Role = 'Admin' } = $adminToken
} -DefaultAuthSession $adminToken -AuthSessionType 'OAuth'

# Workflow steps specify: With.AuthSessionOptions = @{ Role = 'Tier0' }
```

### Auth Session Type

**Required `AuthSessionType`:** `OAuth`

The EntraID provider uses OAuth-based authentication via Microsoft Graph API tokens. When creating the `AuthSessionBroker`, specify `AuthSessionType = 'OAuth'` to indicate token-based authentication is expected.



> Providers must not prompt for auth. Use the host-provided broker contract.

- **Auth session name(s) used by built-in steps:** `MicrosoftGraph`
- **Auth session formats supported:**  
  - `string` Bearer access token  
  - object with `AccessToken` property  
  - object with `GetAccessToken()` method  
  - `PSCredential` (token stored in password field; username is ignored)
- **Session options (data-only):** Any hashtable; common keys: `Role`, `Tenant`, `Environment`

:::warning

**Security notes**

- Do not pass secrets in workflow files or provider options.
- If you use access tokens, ensure your host does not log them (events, transcripts, verbose output).

:::

### Auth examples

**A) Delegated auth (interactive) – host obtains token, provider consumes token**

```powershell
# Host responsibility:
# Example with Microsoft Graph PowerShell (interactive sign-in)
Connect-MgGraph -Scopes 'User.ReadWrite.All','Group.ReadWrite.All' | Out-Null
$ctx = Get-MgContext

# Provide a token supplier object so tokens can refresh
$tokenSupplier = [pscustomobject]@{ Context = $ctx }
$tokenSupplier | Add-Member -MemberType ScriptMethod -Name GetAccessToken -Value {
  # NOTE: Replace this with your real token retrieval logic.
  # In many hosts you would acquire tokens via MSAL / managed identity.
  throw 'Implement token acquisition in the host.'
}

$broker = [pscustomobject]@{}
$broker | Add-Member -MemberType ScriptMethod -Name AcquireAuthSession -Value {
  param($Name, $Options)
  return $tokenSupplier
}

$providers = @{
  Identity          = New-IdleEntraIDIdentityProvider
  AuthSessionBroker = $broker
}

# Steps use:
# With.AuthSessionName = 'MicrosoftGraph'
```

**B) App-only auth – host supplies a fixed token string (simple demo / lab)**

```powershell
$accessToken = Get-MyGraphAppOnlyToken # host-managed (MSAL / managed identity / etc.)

$broker = [pscustomobject]@{}
$broker | Add-Member -MemberType ScriptMethod -Name AcquireAuthSession -Value {
  param($Name, $Options)
  return $accessToken
}

$providers = @{
  Identity          = New-IdleEntraIDIdentityProvider
  AuthSessionBroker = $broker
}
```

**C) Multi-tenant routing**

```powershell
$tokenProd = Get-GraphToken -Tenant 'contoso.onmicrosoft.com'
$tokenLab  = Get-GraphToken -Tenant 'contoso-lab.onmicrosoft.com'

$broker = [pscustomobject]@{}
$broker | Add-Member -MemberType ScriptMethod -Name AcquireAuthSession -Value {
  param($Name, $Options)
  if ($Options.Tenant -eq 'Prod') { return $tokenProd }
  if ($Options.Tenant -eq 'Lab')  { return $tokenLab }
  throw "Unknown tenant option: $($Options.Tenant)"
}

# Steps use With.AuthSessionOptions = @{ Tenant = 'Prod' } etc.
```

## Required Microsoft Graph Permissions

### Delegated Permissions (User Context)

Minimum required:

- `User.Read.All` (read user information)
- `User.ReadWrite.All` (create/update/delete users)
- `Group.Read.All` (list group memberships)
- `GroupMember.ReadWrite.All` (add/remove group members)

### Application Permissions (App-Only Context)

Minimum required (same as delegated):

- `User.Read.All`
- `User.ReadWrite.All`
- `Group.Read.All`
- `GroupMember.ReadWrite.All`

**Note**: Application permissions require admin consent in the tenant.

## Capabilities

The provider advertises these capabilities via `GetCapabilities()`:

- `IdLE.Identity.Read` - Read identity information
- `IdLE.Identity.List` - List identities (filter support varies)
- `IdLE.Identity.Create` - Create new identities
- `IdLE.Identity.Attribute.Ensure` - Set/update identity attributes
- `IdLE.Identity.Disable` - Disable user accounts
- `IdLE.Identity.Enable` - Enable user accounts
- `IdLE.Entitlement.List` - List group memberships
- `IdLE.Entitlement.Grant` - Add group membership
- `IdLE.Entitlement.Revoke` - Remove group membership
- `IdLE.Identity.Delete` - **Opt-in only** (see Safety section)

## Identity Addressing

### Lookup Modes

The provider supports multiple ways to reference an identity:

| Format | Example | Notes |
|--------|---------|-------|
| objectId (GUID) | `"a1b2c3d4-e5f6-7890-abcd-ef1234567890"` | Most deterministic |
| UserPrincipalName (UPN) | `"user@contoso.com"` | Contains `@` |
| mail | `"user.name@contoso.com"` | Fallback if UPN lookup fails |

### Canonical Identity Key

**All provider methods return the user objectId (GUID) as the canonical IdentityKey.**

This ensures deterministic identity references across workflows and is the recommended format for workflow definitions.

### Resolution Rules

1. If the input is a valid GUID format, look up by objectId
2. If the input contains `@`, try UPN lookup, then mail lookup
3. Otherwise, throw an error

## Entitlement Model (Groups)

### Entitlement Object Format

```powershell
@{
    Kind = 'Group'
    Id   = '<group objectId GUID>'  # Canonical
    DisplayName = 'Group Display Name'  # Optional
    Mail = 'group@contoso.com'  # Optional
}
```

### Group Resolution

The provider accepts group references in two formats:

1. **objectId (GUID)** - Direct lookup (most reliable)
2. **displayName** - Lookup by name (must be unique)

#### Ambiguity Handling

If multiple groups share the same displayName, the provider throws an error. Use objectId for deterministic lookup.

### Idempotency

All group operations are idempotent:

- **Grant**: Returns `Changed = $false` if already a member
- **Revoke**: Returns `Changed = $false` if not a member

## Safety: Delete Capability

### Default Behavior (Delete Disabled)

By default, the `IdLE.Identity.Delete` capability is **NOT advertised** and delete operations will fail.

```powershell
$provider = New-IdleEntraIDIdentityProvider
# Delete is NOT available
```

### Opt-In for Delete

To enable delete capability, use the `-AllowDelete` switch:

```powershell
$provider = New-IdleEntraIDIdentityProvider -AllowDelete
# Delete is now available
```

### Workflow Requirements

Workflows that require delete must explicitly declare the capability requirement in their metadata (not yet implemented in IdLE core, but provider is ready).

## Transient Error Handling

The provider classifies errors as transient or permanent for retry policy support.

### Transient Errors (Retryable)

These errors set `Exception.Data['Idle.IsTransient'] = $true`:

- HTTP 429 (Rate limiting)
- HTTP 5xx (Server errors)
- HTTP 408 (Request timeout)
- Network timeouts

### Retry Metadata

Transient errors include metadata in the exception message:

- HTTP status code
- Microsoft Graph request ID (if available)
- `Retry-After` header (if present)

**Note**: The provider does NOT perform retries automatically. Retry policy is a host concern.

## Supported Attributes

### Identity Attributes

These attributes can be set via `CreateIdentity` and `EnsureAttribute`:

| Attribute | Graph Property | Notes |
|-----------|---------------|-------|
| `GivenName` | `givenName` | First name |
| `Surname` | `surname` | Last name |
| `DisplayName` | `displayName` | Display name (required for create) |
| `UserPrincipalName` | `userPrincipalName` | UPN (required for create) |
| `Mail` | `mail` | Email address |
| `Department` | `department` | Department |
| `JobTitle` | `jobTitle` | Job title |
| `OfficeLocation` | `officeLocation` | Office location |
| `CompanyName` | `companyName` | Company name |
| `MailNickname` | `mailNickname` | Mail alias (auto-generated if not provided) |
| `PasswordProfile` | `passwordProfile` | Password policy for new users |
| `Enabled` | `accountEnabled` | Account enabled state |

### Password Policy (Create Only)

When creating users, provide a `PasswordProfile`:

```powershell
$attributes = @{
    UserPrincipalName = 'newuser@contoso.com'
    DisplayName = 'New User'
    PasswordProfile = @{
        forceChangePasswordNextSignIn = $true
        password = 'Temp@Pass123!'
    }
}
```

If not provided, a random password is generated with `forceChangePasswordNextSignIn = $true`.

## Paging

The provider automatically handles Microsoft Graph paging for `ListUsers` and `ListUserGroups` operations using the `@odata.nextLink` continuation token.

No additional configuration required.

## Built-in Steps Compatibility

The provider works with these built-in IdLE steps:

- `IdLE.Step.CreateIdentity`
- `IdLE.Step.EnsureAttribute`
- `IdLE.Step.DisableIdentity`
- `IdLE.Step.EnableIdentity`
- `IdLE.Step.DeleteIdentity` (when `AllowDelete = $true`)
- `IdLE.Step.EnsureEntitlement`

## Workflow Configuration

### Recommended AuthSession Routing

- `With.AuthSessionName = 'MicrosoftGraph'`
- `With.AuthSessionOptions = @{ Role = 'Admin' }` (or other routing keys)

### Example Step Definition

```powershell
@{
    Id = 'CreateUser'
    Type = 'IdLE.Step.CreateIdentity'
    With = @{
        AuthSessionName = 'MicrosoftGraph'
        AuthSessionOptions = @{ Role = 'Admin' }
        Attributes = @{
            UserPrincipalName = 'newuser@contoso.com'
            DisplayName = 'New User'
            GivenName = 'New'
            Surname = 'User'
        }
    }
}
```

## Limitations

- **Supported API version**: v1.0 (beta endpoints not used)
- **Group types**: Only Entra ID groups (not M365 groups or distribution lists)
- **Licensing**: The provider does NOT manage license assignments
- **MFA/Conditional Access**: Not managed by provider
- **Custom attributes/extensions**: Not supported in MVP

## Troubleshooting

### "AuthSession is required"

Ensure you're passing an `AuthSessionBroker` to `New-IdlePlan` and that steps are using `With.AuthSessionName`.

### "Multiple groups found with displayName"

Use the group objectId instead of displayName for deterministic lookup.

### "429 Too Many Requests"

Microsoft Graph enforces rate limits. The provider marks these as transient errors. Implement retry logic in your host or reduce request frequency.

### "Insufficient permissions"

Verify the access token has the required Graph API permissions (see Required Permissions section).

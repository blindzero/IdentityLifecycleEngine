---
title: Provider Reference - IdLE.Provider.EntraID
sidebar_label: Entra ID
---

> **Purpose:** This page is a **reference** for a specific provider implementation.
> Keep it factual and contract-oriented. Put conceptual explanations elsewhere and link to them.

---

## Summary

- **Provider name:** `EntraID` (Microsoft Entra ID)
- **Module:** `IdLE.Provider.EntraID`
- **Provider kind:** `Identity | Entitlement`
- **Targets:** Microsoft Entra ID (formerly Azure Active Directory) via Microsoft Graph API (v1.0)
- **Status:** First-party (bundled)
- **Since:** 0.9.0
- **Compatibility:** PowerShell 7+ (IdLE requirement)

---

## What this provider does

- **Primary responsibilities:**
  - Create, read, update, disable, enable, and delete (opt-in) user accounts in Microsoft Entra ID
  - Set and update user attributes (givenName, surname, department, jobTitle, etc.)
  - List group memberships and manage group entitlements (grant/revoke)
  - Resolve identities by objectId (GUID), UserPrincipalName (UPN), or mail address
- **Out of scope / non-goals:**
  - Establishing authentication or obtaining Graph access tokens (handled by host-provided broker)
  - Managing M365 groups, distribution lists, or Teams
  - License assignment or MFA/Conditional Access management
  - Custom attributes or schema extensions (not supported in MVP)

---

## Contracts and capabilities

### Contracts implemented

| Contract | Used by steps for | Notes |
| --- | --- | --- |
| Identity provider (implicit) | Identity read/write/delete operations | Full identity lifecycle support via Microsoft Graph API |
| Entitlement provider (implicit) | Grant/revoke/list group memberships | Only Entra ID groups; not M365 groups or distribution lists |

### Capability advertisement (`GetCapabilities()`)

- **Implements `GetCapabilities()`**: Yes
- **Capabilities returned (stable identifiers):**
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

---

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

# Create broker
$broker = New-IdleAuthSession -SessionMap @{
    @{} = $token
} -DefaultCredential $token

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

# Create broker
$broker = New-IdleAuthSession -SessionMap @{
    @{} = $token
} -DefaultCredential $token

# Rest is identical to delegated flow
```

### Example: Multi-Role Scenario

```powershell
$tier0Token = Get-GraphToken -Role 'Tier0'
$adminToken = Get-GraphToken -Role 'Admin'

$broker = New-IdleAuthSession -SessionMap @{
    @{ Role = 'Tier0' } = $tier0Token
    @{ Role = 'Admin' } = $adminToken
} -DefaultCredential $adminToken

# Workflow steps specify: With.AuthSessionOptions = @{ Role = 'Tier0' }
```



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

---

## Configuration

### Provider constructor / factory

How to create an instance.

- **Public constructor cmdlet(s):**
  - `New-IdleEntraIDIdentityProvider` — Creates an Entra ID identity provider instance

**Parameters (high signal only)**

- `-AllowDelete` (switch) — Opt-in to enable the `IdLE.Identity.Delete` capability (disabled by default for safety)

> Do not copy full comment-based help here. Link to the cmdlet reference.

### Provider bag / alias usage

How to pass the provider instance to IdLE as part of the host's provider map.

```powershell
$providers = @{
  Identity = New-IdleEntraIDIdentityProvider
}
```

- **Recommended alias pattern:** `Identity` (single provider) or `TargetEntra` (multi-provider scenarios)
- **Default alias expected by built-in steps (if any):** `Identity` (if applicable)

---

## Provider-specific options reference

> Document only **data-only** keys. Keep this list short and unambiguous.

This provider has **no provider-specific option bag**. All configuration is done through the constructor parameters and authentication is managed via the `AuthSessionBroker`.

---

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

---

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

---

## Operational behavior

### Idempotency and consistency

- **Idempotent operations:** Yes (all operations)
- **Consistency model:** Eventually consistent (Microsoft Graph API)
- **Concurrency notes:** Microsoft Graph enforces rate limits; provider marks throttling errors as transient

All operations are idempotent:

| Operation | Idempotent Behavior |
| --------- | ------------------- |
| Create | If identity exists, returns `Changed=$false` (no error) |
| Delete | If identity already gone, returns `Changed=$false` (no error) |
| Enable/Disable | If already in desired state, returns `Changed=$false` |
| Grant membership | If already a member, returns `Changed=$false` |
| Revoke membership | If not a member, returns `Changed=$false` |
| Set attribute | If already at desired value, returns `Changed=$false` |

### Error mapping and retry behavior

- **Common error categories:** `NotFound`, `AlreadyExists`, `PermissionDenied`, `Throttled` (HTTP 429)
- **Retry strategy:** None (provider marks transient errors; retry is delegated to host)

---

## Observability

- **Events emitted by provider (if any):**
  - Steps emit events via the execution context; provider operations are traced through step events
- **Sensitive data redaction:** Access tokens and credential objects are not included in operation results or events

---

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

---

## Examples

### Minimal host usage

```powershell
# 1) Create provider instance
$provider = New-IdleEntraIDIdentityProvider

# 2) Obtain Graph token (host responsibility)
$token = (Get-AzAccessToken -ResourceUrl "https://graph.microsoft.com").Token

# 3) Create broker
$broker = New-IdleAuthSession -SessionMap @{ @{} = $token } -DefaultCredential $token

# 4) Build provider map
$providers = @{
  Identity = $provider
  AuthSessionBroker = $broker
}

# 5) Plan + execute
$plan = New-IdlePlan -WorkflowPath './workflow.psd1' -Request $request -Providers $providers
$result = Invoke-IdlePlan -Plan $plan -Providers $providers
```

### Example workflow snippet

```powershell
@{
  Steps = @(
    @{
      Name = 'CreateUser'
      Type = 'IdLE.Step.CreateIdentity'
      With = @{
        Provider = 'Identity'
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
  )
}
```

---

## Built-in Steps Compatibility

The provider works with these built-in IdLE steps:

- `IdLE.Step.CreateIdentity`
- `IdLE.Step.EnsureAttribute`
- `IdLE.Step.DisableIdentity`
- `IdLE.Step.EnableIdentity`
- `IdLE.Step.DeleteIdentity` (when `AllowDelete = $true`)
- `IdLE.Step.EnsureEntitlement`

---

## Limitations and known issues

- **Supported API version**: v1.0 (beta endpoints not used)
- **Group types**: Only Entra ID groups (not M365 groups or distribution lists)
- **Licensing**: The provider does NOT manage license assignments
- **MFA/Conditional Access**: Not managed by provider
- **Custom attributes/extensions**: Not supported in MVP

---

## Testing

- **Unit tests:** `tests/Providers/EntraIDIdentityProvider.Tests.ps1`
- **Contract tests:** Provider contract tests validate implementation compliance
- **Known CI constraints:** Tests use mock HTTP layer; no live Microsoft Graph calls in CI

---

## Troubleshooting

### "AuthSession is required"

Ensure you're passing an `AuthSessionBroker` to `New-IdlePlan` and that steps are using `With.AuthSessionName`.

### "Multiple groups found with displayName"

Use the group objectId instead of displayName for deterministic lookup.

### "429 Too Many Requests"

Microsoft Graph enforces rate limits. The provider marks these as transient errors. Implement retry logic in your host or reduce request frequency.

### "Insufficient permissions"

Verify the access token has the required Graph API permissions (see Required Permissions section).

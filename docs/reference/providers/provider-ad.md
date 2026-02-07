---
title: Provider Reference - IdLE.Provider.AD (Active Directory)
sidebar_label: Active Directory
---

## Summary

- **Provider name:** `AD` (Active Directory)
- **Module:** `IdLE.Provider.AD`
- **Provider kind:** `Identity | Entitlement`
- **Targets:** Windows Active Directory (on-premises domains)
- **Status:** Built-in
- **Since:** 0.9.0
- **Compatibility:** PowerShell 7+ (IdLE requirement), Windows-only (requires RSAT/ActiveDirectory PowerShell module)

---

## What this provider does

- **Primary responsibilities:**
  - Create, read, update, disable, enable, and delete (opt-in) user accounts in Active Directory
  - Set and update user attributes (department, title, office location, etc.)
  - Move users between organizational units (OUs)
  - Manage group memberships (grant/revoke entitlements)
- **Out of scope / non-goals:**
  - Establishing AD connectivity or authentication (handled by host-provided credentials or integrated auth)
  - Managing group policy objects (GPOs)
  - Managing other AD object types (computers, contacts, etc.)

---

## Contracts and capabilities

### Contracts implemented

List the IdLE provider contracts this provider implements and what they mean at a glance.

| Contract | Used by steps for | Notes |
| --- | --- | --- |
| Identity provider (implicit) | Identity read/write operations | Supports comprehensive identity lifecycle operations including OU moves |
| Entitlement provider (implicit) | Grant/revoke/list entitlements | Only supports `Kind='Group'` (AD platform limitation) |

> Keep the contract list stable and link to the canonical contract reference.

### Capability advertisement (`GetCapabilities()`)

- **Implements `GetCapabilities()`**: Yes
- **Capabilities returned (stable identifiers):**
  - `IdLE.Identity.Read` - Query identity information
  - `IdLE.Identity.List` - List identities (provider API only, no built-in step)
  - `IdLE.Identity.Create` - Create new user accounts
  - `IdLE.Identity.Delete` - Delete user accounts (opt-in via `-AllowDelete`)
  - `IdLE.Identity.Disable` - Disable user accounts
  - `IdLE.Identity.Enable` - Enable user accounts
  - `IdLE.Identity.Move` - Move users between OUs
  - `IdLE.Identity.Attribute.Ensure` - Set/update user attributes
  - `IdLE.Entitlement.List` - List group memberships
  - `IdLE.Entitlement.Grant` - Add users to groups
  - `IdLE.Entitlement.Revoke` - Remove users from groups

**Note:** AD only supports `Kind='Group'` for entitlements. This is a platform limitation - Active Directory only provides security groups and distribution groups, not arbitrary entitlement types (roles, licenses, etc.).

---

## Authentication and session acquisition

> Providers must not prompt for auth. Use the host-provided broker contract.

- **Auth session name(s) requested via `Context.AcquireAuthSession(...)`:**
  - `ActiveDirectory`
- **Session options (data-only):**
  - Any hashtable; commonly `@{ Role = 'Tier0' }` or `@{ Role = 'Admin' }` or `@{ Domain = 'SourceForest' }`
- **Auth session formats supported:**
  - `$null` (integrated authentication / run-as context)
  - `PSCredential` (used for AD cmdlets `-Credential` parameter)

:::warning

**Security notes**

- Do not pass secrets in workflow files or provider options.
- Ensure credential objects (or their secure strings) are not emitted in logs/events.

:::

---

## Prerequisites

### Windows and RSAT

The provider requires Windows with the Active Directory PowerShell module (RSAT).

**Install RSAT on Windows Server:**
```powershell
Install-WindowsFeature -Name RSAT-AD-PowerShell
```

**Install RSAT on Windows 10/11:**
```powershell
Get-WindowsCapability -Online -Name "Rsat.ActiveDirectory*" | Add-WindowsCapability -Online
```

### Active Directory Permissions

The account running IdLE (or provided via `-Credential`) must have appropriate AD permissions:

| Operation | Required Permission |
| --------- | ------------------- |
| Read identity | Read access to user objects |
| Create identity | Create user objects in target OU |
| Delete identity | Delete user objects |
| Disable/Enable | Modify user account flags |
| Set attributes | Write access to specific attributes |
| Move identity | Move objects between OUs |
| Grant/Revoke group membership | Modify group membership |

Follow the principle of least privilege - grant only the permissions required for your workflows.

---

## Installation and Import

The AD provider is automatically imported when you import the main IdLE module:

```powershell
Import-Module IdLE
```

This makes `New-IdleADIdentityProvider` available in your session.

---

## Configuration

### Provider constructor / factory

How to create an instance.

- **Public constructor cmdlet(s):**
  - `New-IdleADIdentityProvider` — Creates an Active Directory identity provider instance

**Parameters (high signal only)**

- `-AllowDelete` (switch) — Opt-in to enable the `IdLE.Identity.Delete` capability (disabled by default for safety)

> Do not copy full comment-based help here. Link to the cmdlet reference.

### Provider bag / alias usage

How to pass the provider instance to IdLE as part of the host's provider map.

```powershell
$providers = @{
  Identity = New-IdleADIdentityProvider
}
```

- **Recommended alias pattern:** `Identity` (single provider) or `SourceAD` / `TargetAD` (multi-provider scenarios)
- **Default alias expected by built-in steps (if any):** `Identity` (if applicable)

---

## Provider-specific options reference

> Document only **data-only** keys. Keep this list short and unambiguous.

This provider has **no provider-specific option bag**. All configuration is done through the constructor parameters and authentication is managed via the `AuthSessionBroker`.

---

## Auth examples (Authentication patterns)

**A) Integrated authentication (no broker)**

```powershell
# Run the host under an account that already has the required AD permissions.
$providers = @{
  Identity = New-IdleADIdentityProvider
}
```

**B) Role-based routing with `New-IdleAuthSession` (typical Tier0/Admin)**

```powershell
$tier0Credential = Get-Credential -Message 'Enter Tier0 AD admin credentials'
$adminCredential = Get-Credential -Message 'Enter AD admin credentials'

$broker = New-IdleAuthSession -SessionMap @{
  @{ Role = 'Tier0' } = $tier0Credential
  @{ Role = 'Admin' } = $adminCredential
} -DefaultCredential $adminCredential

$providers = @{
  Identity         = New-IdleADIdentityProvider
  AuthSessionBroker = $broker
}

# In the workflow step:
# With.AuthSessionName    = 'ActiveDirectory'
# With.AuthSessionOptions = @{ Role = 'Tier0' }
```

**C) Multi-forest / multi-domain routing**

```powershell
$sourceCred = Get-Credential -Message 'Enter credentials for source forest'
$targetCred = Get-Credential -Message 'Enter credentials for target forest'

$broker = New-IdleAuthSession -SessionMap @{
  @{ Domain = 'SourceForest' } = $sourceCred
  @{ Domain = 'TargetForest' } = $targetCred
}

# Steps use With.AuthSessionOptions = @{ Domain = 'SourceForest' } etc.
```

---

## Operational behavior

### Idempotency and consistency

- **Idempotent operations:** Yes (all operations)
- **Consistency model:** Strong (Active Directory platform consistency)
- **Concurrency notes:** Operations are safe for retries. AD handles concurrent operations natively.

All operations are idempotent and safe for retries:

| Operation | Idempotent Behavior |
| --------- | ------------------- |
| Create | If identity exists, returns `Changed=$false` (no error) |
| Delete | If identity already gone, returns `Changed=$false` (no error) |
| Move | If already in target OU, returns `Changed=$false` |
| Enable/Disable | If already in desired state, returns `Changed=$false` |
| Grant membership | If already a member, returns `Changed=$false` |
| Revoke membership | If not a member, returns `Changed=$false` |

This design ensures workflows can be re-run safely without causing duplicate operations or errors.

### Error mapping and retry behavior

- **Common error categories:** `NotFound`, `AlreadyExists`, `PermissionDenied`, `ObjectNotFound`
- **Retry strategy:** none (delegated to host)

---

## Observability

- **Events emitted by provider (if any):**
  - Steps emit events via the execution context; provider operations are traced through step events
- **Sensitive data redaction:** Credential objects and secure strings are not included in operation results or events

---

## Usage

### Basic Usage (Integrated Auth)

```powershell
# Create provider using integrated authentication (run-as)
$provider = New-IdleADIdentityProvider

# Use in workflows
$plan = New-IdlePlan -WorkflowPath './workflow.psd1' -Request $request -Providers @{
    Identity = $provider
}
```

### AuthSessionBroker-based Authentication

Use an AuthSessionBroker to manage authentication centrally and enable multi-role scenarios.

**Simple approach with New-IdleAuthSession:**

```powershell
# Assuming you have credentials available (e.g., from a secure vault or credential manager)
$tier0Credential = Get-Credential -Message "Enter Tier0 admin credentials"
$adminCredential = Get-Credential -Message "Enter regular admin credentials"

# Create provider
$provider = New-IdleADIdentityProvider

# Create broker with role-based credential mapping
$broker = New-IdleAuthSession -SessionMap @{
    @{ Role = 'Tier0' } = $tier0Credential
    @{ Role = 'Admin' } = $adminCredential
} -DefaultCredential $adminCredential

# Use provider with broker
$plan = New-IdlePlan -WorkflowPath './workflow.psd1' -Request $request -Providers @{
    Identity = $provider
    AuthSessionBroker = $broker
}
```

**Custom broker for advanced scenarios:**

For advanced scenarios (vault integration, MFA, dynamic credential retrieval), implement a custom broker:

```powershell
$broker = [pscustomobject]@{}
$broker | Add-Member -MemberType ScriptMethod -Name AcquireAuthSession -Value {
    param($Name, $Options)
    # Custom logic: retrieve from vault, prompt for MFA, etc.
    if ($Options.Role -eq 'Tier0') {
        return Get-SecretFromVault -Name 'AD-Tier0'
    }
    return Get-SecretFromVault -Name 'AD-Admin'
}
```

In workflow definitions, steps specify which auth context to use via `AuthSessionOptions`:

```powershell
@{
    Type = 'IdLE.Step.EnsureAttribute'
    Name = 'SetPrivilegedAttribute'
    With = @{
        IdentityKey = 'user@domain.com'
        Name = 'AdminCount'
        Value = 1
        AuthSessionName = 'ActiveDirectory'
        AuthSessionOptions = @{ Role = 'Tier0' }  # Broker returns Tier0 credential
    }
}

@{
    Type = 'IdLE.Step.EnsureAttribute'
    Name = 'SetDepartment'
    With = @{
        IdentityKey = 'user@domain.com'
        Name = 'Department'
        Value = 'IT'
        AuthSessionName = 'ActiveDirectory'
        AuthSessionOptions = @{ Role = 'Admin' }  # Broker returns Admin credential
    }
}
```

**Key points:**
- The `Role` key (or any other key) is **defined by you** - it's not a built-in keyword
- Your broker implementation decides how to interpret `AuthSessionOptions`
- The broker can use any logic you want: hashtable lookups, vault APIs, interactive prompts, etc.
- `AuthSessionOptions` must be data-only (no ScriptBlocks) for security

### With Delete Capability (Opt-in)

By default, the Delete capability is **not** advertised for safety. Enable it explicitly:

```powershell
$provider = New-IdleADIdentityProvider -AllowDelete
```

### Multi-Provider Scenarios

For scenarios with multiple AD forests or domains, use provider aliases with the AuthSessionBroker:

```powershell
# Assuming you have credentials for each domain
$sourceCred = Get-Credential -Message "Enter Source AD admin credentials"
$targetCred = Get-Credential -Message "Enter Target AD admin credentials"

# Create providers for different AD environments
$sourceAD = New-IdleADIdentityProvider
$targetAD = New-IdleADIdentityProvider -AllowDelete

# Use New-IdleAuthSession for domain-based credential routing
$broker = New-IdleAuthSession -SessionMap @{
    @{ Domain = 'Source' } = $sourceCred
    @{ Domain = 'Target' } = $targetCred
}

$plan = New-IdlePlan -WorkflowPath './migration.psd1' -Request $request -Providers @{
    SourceAD = $sourceAD
    TargetAD = $targetAD
    AuthSessionBroker = $broker
}
```

Workflow steps specify which domain to authenticate against:

```powershell
@{
    Type = 'IdLE.Step.GetIdentity'
    Name = 'ReadSource'
    With = @{
        IdentityKey = 'user@source.com'
        Provider = 'SourceAD'
        AuthSessionName = 'ActiveDirectory'
        AuthSessionOptions = @{ Domain = 'Source' }
    }
}

@{
    Type = 'IdLE.Step.CreateIdentity'
    Name = 'CreateTarget'
    With = @{
        IdentityKey = 'user@target.com'
        Attributes = @\{ ... \}
        Provider = 'TargetAD'
        AuthSessionName = 'ActiveDirectory'
        AuthSessionOptions = @{ Domain = 'Target' }
    }
}
```

---

## Identity Resolution

The provider supports multiple identifier formats and resolves them deterministically:

1. **GUID** (ObjectGuid): Pattern matches `[System.Guid]::TryParse()` - most deterministic
2. **UPN** (UserPrincipalName): Contains `@` symbol
3. **sAMAccountName**: Fallback for simple usernames

**Resolution order:**
```powershell
# GUID format → resolve by ObjectGuid
'a1b2c3d4-e5f6-7890-abcd-ef1234567890'

# Contains @ → resolve by UPN
'john.doe@contoso.local'

# Otherwise → resolve by sAMAccountName
'jdoe'
```

**Canonical output:** The provider returns the input IdentityKey as-is in operation results to maintain workflow consistency.

**Error handling:** On ambiguous or missing identities, the provider throws deterministic errors (no best-effort guessing).

---

## Entitlement Model

Active Directory entitlements use:

- **Kind:** Always `'Group'` (AD limitation - only supports security and distribution groups)
- **Id (canonical key):** DistinguishedName (DN)

**Input flexibility:** The provider MAY accept SID or sAMAccountName as input but MUST normalize to DN internally.

**Example:**
```powershell
@{
    Kind = 'Group'
    Id   = 'CN=IT-Team,OU=Groups,DC=contoso,DC=local'
}
```

---

## Built-in Steps

The following built-in steps in `IdLE.Steps.Common` work with the AD provider:

- **IdLE.Step.CreateIdentity** - Create new user accounts
- **IdLE.Step.DisableIdentity** - Disable user accounts
- **IdLE.Step.EnableIdentity** - Enable user accounts
- **IdLE.Step.MoveIdentity** - Move users between OUs
- **IdLE.Step.DeleteIdentity** - Delete user accounts (requires `IdLE.Identity.Delete` capability)
- **IdLE.Step.EnsureAttribute** - Set/update user attributes
- **IdLE.Step.EnsureEntitlement** - Manage group memberships

Step metadata (including required capabilities) is provided by step pack modules (`IdLE.Steps.Common`) and used for plan-time validation.

---

## Examples

### Minimal host usage

```powershell
# 1) Create provider instance
$provider = New-IdleADIdentityProvider

# 2) Build provider map
$providers = @{ Identity = $provider }

# 3) Plan + execute
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
        IdentityKey = 'jdoe'
        Attributes = @{
          GivenName = 'John'
          Surname = 'Doe'
          UserPrincipalName = 'jdoe@contoso.local'
        }
        AuthSessionName = 'ActiveDirectory'
        AuthSessionOptions = @{ Role = 'Admin' }
      }
    }
  )
}
```

### Complete example workflows

Complete example workflows are available in the repository:

- **examples/workflows/ad-joiner-complete.psd1** - Full joiner workflow (Create + Attributes + Groups + OU move)
- **examples/workflows/ad-mover-department-change.psd1** - Mover workflow (Update attributes + Group delta + OU move)
- **examples/workflows/ad-leaver-offboarding.psd1** - Leaver workflow (Disable + OU move + conditional Delete)

---

## Limitations and known issues

- **Platform:** Windows-only (requires RSAT/ActiveDirectory PowerShell module)
- **Entitlement types:** Only supports `Kind='Group'` (AD platform limitation - no roles, licenses, etc.)
- **Concurrency:** While operations are thread-safe, concurrent modifications to the same object should be managed by the host
- **Delete capability:** Disabled by default; must opt-in with `-AllowDelete` for safety

---

## Testing

- **Unit tests:** `tests/Providers/ADIdentityProvider.Tests.ps1`
- **Contract tests:** Provider contract tests validate implementation compliance
- **Known CI constraints:** Tests use mock adapter layer; no live AD dependency in CI

---

## Troubleshooting

### ActiveDirectory Module Not Found

**Error:** `The specified module 'ActiveDirectory' was not loaded...`

**Solution:** Install RSAT as described in Prerequisites.

### Insufficient Permissions

**Error:** `Insufficient access rights to perform the operation`

**Solution:** Verify the account has required AD permissions. Use a dedicated service account with least-privilege access.

### Identity Not Found

**Error:** `Identity with &lt;identifier&gt; not found`

**Solution:** 
- Verify the identifier format (GUID/UPN/sAMAccountName)
- Check the user exists in AD
- Ensure the account has read access to the user object

### Delete Capability Missing

**Error:** Plan validation fails with `Required capability 'IdLE.Identity.Delete' not available`

**Solution:** Create the provider with `-AllowDelete` parameter:
```powershell
$provider = New-IdleADIdentityProvider -AllowDelete
```

---

## Architecture Notes

### Testability

The AD provider uses an internal adapter layer (`New-IdleADAdapter`) that isolates AD cmdlet dependencies. This design:

- Enables unit testing without real AD (unit tests inject fake adapters)
- Keeps provider logic testable and deterministic
- Separates provider contract from AD implementation details

### Security

- **No interactive prompts:** The provider never prompts for credentials (violates headless principle)
- **Opt-in Delete:** Delete capability requires explicit `-AllowDelete` for safety
- **Credential handling:** Credentials are passed to AD cmdlets securely via `-Credential` parameter

### Capability-Driven Design

The provider implements `GetCapabilities()` and announces all supported capabilities. The engine validates capabilities at plan-time before execution, enabling fail-fast behavior.

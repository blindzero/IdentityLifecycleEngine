# IdLE.Provider.AD - Active Directory Provider

## Overview

The Active Directory provider (`IdLE.Provider.AD`) is a built-in provider for on-premises Active Directory environments. It enables IdLE to perform identity lifecycle operations directly against Windows Active Directory domains.

**Platform:** Windows-only (requires RSAT/ActiveDirectory PowerShell module)

**Module:** IdLE.Provider.AD

**Factory Function:** `New-IdleADIdentityProvider`

---

## Capabilities

The AD provider implements the following IdLE capabilities:

### Identity Operations

- **IdLE.Identity.Read** - Query identity information
- **IdLE.Identity.List** - List identities (provider API only, no built-in step)
- **IdLE.Identity.Create** - Create new user accounts
- **IdLE.Identity.Delete** - Delete user accounts (opt-in via `-AllowDelete`)
- **IdLE.Identity.Disable** - Disable user accounts
- **IdLE.Identity.Enable** - Enable user accounts
- **IdLE.Identity.Move** - Move users between OUs
- **IdLE.Identity.Attribute.Ensure** - Set/update user attributes

### Entitlement Operations

- **IdLE.Entitlement.List** - List group memberships
- **IdLE.Entitlement.Grant** - Add users to groups
- **IdLE.Entitlement.Revoke** - Remove users from groups

**Note:** AD only supports `Kind='Group'` for entitlements. This is a platform limitation - Active Directory only provides security groups and distribution groups, not arbitrary entitlement types (roles, licenses, etc.).

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

**Simple approach with New-IdleAuthSessionBroker:**

```powershell
# Assuming you have credentials available (e.g., from a secure vault or credential manager)
$tier0Credential = Get-Credential -Message "Enter Tier0 admin credentials"
$adminCredential = Get-Credential -Message "Enter regular admin credentials"

# Create provider
$provider = New-IdleADIdentityProvider

# Create broker with role-based credential mapping
$broker = New-IdleAuthSessionBroker -SessionMap @{
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

# Use New-IdleAuthSessionBroker for domain-based credential routing
$broker = New-IdleAuthSessionBroker -SessionMap @{
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
        Attributes = @{ ... }
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

## Idempotency Guarantees

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

## Example Workflows

Complete example workflows are available in the repository:

- **examples/workflows/ad-joiner-complete.psd1** - Full joiner workflow (Create + Attributes + Groups + OU move)
- **examples/workflows/ad-mover-department-change.psd1** - Mover workflow (Update attributes + Group delta + OU move)
- **examples/workflows/ad-leaver-offboarding.psd1** - Leaver workflow (Disable + OU move + conditional Delete)

---

## Provider Aliases

The provider uses **provider aliases** - the hashtable key in the `Providers` parameter is an alias chosen by the host:

```powershell
# Single provider scenario
$plan = New-IdlePlan -Providers @{ Identity = $provider }

# Multi-provider scenario
$plan = New-IdlePlan -Providers @{ 
    SourceAD = $sourceProvider
    TargetAD = $targetProvider 
}
```

Workflow steps reference the alias via `With.Provider`:

```powershell
@{
    Type = 'IdLE.Step.CreateIdentity'
    With = @{
        Provider = 'SourceAD'  # Matches the alias in Providers hashtable
        IdentityKey = 'user@contoso.local'
        # ...
    }
}
```

Built-in steps default to `'Identity'` when `With.Provider` is omitted.

---

## Troubleshooting

### ActiveDirectory Module Not Found

**Error:** `The specified module 'ActiveDirectory' was not loaded...`

**Solution:** Install RSAT as described in Prerequisites.

### Insufficient Permissions

**Error:** `Insufficient access rights to perform the operation`

**Solution:** Verify the account has required AD permissions. Use a dedicated service account with least-privilege access.

### Identity Not Found

**Error:** `Identity with <identifier> not found`

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

---

## Related Documentation

- [Providers and Contracts](providers-and-contracts.md) - Provider architecture and contracts
- [Steps and Metadata](steps-and-metadata.md) - Built-in steps and capability requirements
- [Provider Capability Rules](../advanced/provider-capabilities.md) - Capability naming and validation
- [Security Model](../advanced/security.md) - Trust boundaries and security considerations

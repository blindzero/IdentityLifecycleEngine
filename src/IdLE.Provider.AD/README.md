# IdLE.Provider.AD

Active Directory (on-premises) provider for IdLE.

## Platform Support

- **Windows only** (requires RSAT/ActiveDirectory module)
- PowerShell 7.0+
- ActiveDirectory PowerShell module

## Prerequisites

### Windows RSAT (Remote Server Administration Tools)

The provider requires the ActiveDirectory PowerShell module, which is part of RSAT.

#### Windows Server

Install the module:

```powershell
Install-WindowsFeature -Name RSAT-AD-PowerShell
```

#### Windows 10/11

Install RSAT features via Settings or use:

```powershell
Get-WindowsCapability -Online -Name "Rsat.ActiveDirectory*" | Add-WindowsCapability -Online
```

### Active Directory Permissions

The account running IdLE (or the account provided via `-Credential`) must have appropriate AD permissions for the operations being performed:

| Operation | Required Permission |
|-----------|---------------------|
| Read identity | Read access to user objects |
| Create identity | Create user objects in target OU |
| Delete identity | Delete user objects (opt-in via `AllowDelete`) |
| Disable/Enable | Modify user account flags |
| Set attributes | Write access to specific attributes |
| Move identity | Move objects between OUs |
| Grant/Revoke group membership | Modify group membership |

For production use, follow the principle of least privilege and grant only the permissions required for your workflows.

## Installation

```powershell
Import-Module IdLE.Provider.AD
```

## Usage

### Basic Usage (Integrated Auth)

```powershell
# Create provider instance using integrated authentication (run-as)
$provider = New-IdleADIdentityProvider

# Use with IdLE plan execution
# The hashtable key 'Identity' is a provider alias - you can use any name you choose.
# Workflow steps reference this alias via With.Provider (defaults to 'Identity' if not specified).
$providers = @{
    Identity = $provider
}

$plan = New-IdlePlan -WorkflowPath '.\workflows\joiner.psd1' -Request $request -Providers $providers
$result = Invoke-IdlePlan -Plan $plan -Providers $providers
```

### Using Custom Provider Aliases

The provider alias (hashtable key) is **not fixed** and can be any name you choose. This is particularly useful when working with multiple provider instances:

```powershell
# Example: Multiple AD forests
$sourceAD = New-IdleADIdentityProvider -Credential $sourceCredential
$targetAD = New-IdleADIdentityProvider -Credential $targetCredential

$providers = @{
    SourceAD = $sourceAD
    TargetAD = $targetAD
}

# In your workflow, specify which provider to use:
# With = @{ IdentityKey = 'user@source.local'; Provider = 'SourceAD' }
# With = @{ IdentityKey = 'user@target.local'; Provider = 'TargetAD' }
```

**Key points:**
- The alias can be any valid PowerShell hashtable key (e.g., `Identity`, `SourceAD`, `SystemX`, `ProdForest`)
- Workflow steps reference the alias via `With.Provider`
- If `With.Provider` is not specified in a step, it defaults to `'Identity'`
- The alias should match between the provider hashtable and the workflow step configuration

### Using Explicit Credentials

```powershell
$cred = Get-Credential
$provider = New-IdleADIdentityProvider -Credential $cred
```

### Enabling Delete Capability (Opt-in)

For safety, the `IdLE.Identity.Delete` capability is **opt-in only**. To enable deletion:

```powershell
$provider = New-IdleADIdentityProvider -AllowDelete
```

Without this flag, the provider will not advertise the Delete capability, and plans requiring deletion will fail during plan validation.

## Capabilities

The AD provider advertises the following capabilities:

| Capability | Description |
|------------|-------------|
| `IdLE.Identity.Read` | Read identity information |
| `IdLE.Identity.List` | List identities (provider API only, no built-in step) |
| `IdLE.Identity.Create` | Create new identities |
| `IdLE.Identity.Delete` | Delete identities (opt-in via `-AllowDelete`) |
| `IdLE.Identity.Attribute.Ensure` | Set/update identity attributes |
| `IdLE.Identity.Move` | Move identities between OUs |
| `IdLE.Identity.Disable` | Disable user accounts |
| `IdLE.Identity.Enable` | Enable user accounts |
| `IdLE.Entitlement.List` | List group memberships |
| `IdLE.Entitlement.Grant` | Add group membership |
| `IdLE.Entitlement.Revoke` | Remove group membership |

## Identity Addressing

The provider supports multiple identity key formats:

### GUID (ObjectGuid)

Pattern: `^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$`

```powershell
$identity = $provider.GetIdentity('a1b2c3d4-e5f6-7890-abcd-ef1234567890')
```

### UPN (UserPrincipalName)

Contains `@`:

```powershell
$identity = $provider.GetIdentity('user@contoso.local')
```

### sAMAccountName

Default fallback (no special pattern):

```powershell
$identity = $provider.GetIdentity('username')
```

### Resolution Rules

- GUID pattern → resolved by `ObjectGuid`
- Contains `@` → resolved by `UserPrincipalName`
- Otherwise → resolved by `sAMAccountName`
- On ambiguous match → throws deterministic error (no best-effort)
- Canonical identity key for outputs: `ObjectGuid` string

## Supported Attributes

When creating or updating identities, the following standard AD attributes are supported:

- `SamAccountName`
- `UserPrincipalName`
- `GivenName`
- `Surname`
- `DisplayName`
- `Description`
- `Department`
- `Title`
- `EmailAddress`
- `Path` (OU/container for new users)

Other attributes can be set using the `Replace` parameter pattern (handled by the adapter).

## Entitlements (Groups)

### Important: AD Only Supports Group Entitlements

Active Directory only supports security groups and distribution groups as entitlements. The AD provider:

- **Only supports** `Kind = 'Group'`
- **Does not support** arbitrary entitlement kinds (e.g., roles, permissions, licenses)
- All entitlements returned by `ListEntitlements` will have `Kind = 'Group'`

This is a fundamental constraint of Active Directory and differs from cloud identity providers that may support multiple entitlement types.

### Group Identification

The provider uses **DistinguishedName (DN)** as the canonical group identifier:

```powershell
@{
    Kind = 'Group'
    Id   = 'CN=IT-Department,OU=Groups,DC=contoso,DC=local'
}
```

The provider **may accept** SID or sAMAccountName as input and will **normalize to DN** internally.

### Group Operations

```powershell
# List current group memberships
$groups = $provider.ListEntitlements('user@contoso.local')

# Grant group membership
$result = $provider.GrantEntitlement('user@contoso.local', @{
    Kind = 'Group'
    Id   = 'CN=Developers,OU=Groups,DC=contoso,DC=local'
})

# Revoke group membership
$result = $provider.RevokeEntitlement('user@contoso.local', @{
    Kind = 'Group'
    Id   = 'CN=Developers,OU=Groups,DC=contoso,DC=local'
})
```

## Idempotency Guarantees

All provider operations are idempotent and safe for retries/reruns:

| Operation | Already in Desired State | Result |
|-----------|--------------------------|--------|
| Create | Identity exists | `Changed = $false` (no duplicate) |
| Delete | Identity already deleted | `Changed = $false` (no error) |
| Disable | Already disabled | `Changed = $false` |
| Enable | Already enabled | `Changed = $false` |
| Move | Already in target OU | `Changed = $false` |
| Grant | Membership already exists | `Changed = $false` |
| Revoke | Membership already absent | `Changed = $false` |

## Built-in Steps

The following built-in steps are available for use with the AD provider:

| Step Type | Capability Required | Description |
|-----------|---------------------|-------------|
| `IdLE.Step.CreateIdentity` | `IdLE.Identity.Create` | Create a new identity |
| `IdLE.Step.DisableIdentity` | `IdLE.Identity.Disable` | Disable an identity |
| `IdLE.Step.EnableIdentity` | `IdLE.Identity.Enable` | Enable an identity |
| `IdLE.Step.MoveIdentity` | `IdLE.Identity.Move` | Move identity to target OU |
| `IdLE.Step.DeleteIdentity` | `IdLE.Identity.Delete` | Delete identity (opt-in) |
| `IdLE.Step.EnsureAttribute` | `IdLE.Identity.Attribute.Ensure` | Set identity attributes |
| `IdLE.Step.EnsureEntitlement` | `IdLE.Entitlement.*` | Grant/Revoke group membership |

## Example Workflows

See `examples/workflows/`:

- `ad-joiner-complete.psd1` - Complete joiner workflow (Create + Attributes + Groups + Move)
- `ad-mover-department-change.psd1` - Mover workflow (Update attributes + Group delta + Move)
- `ad-leaver-offboarding.psd1` - Leaver workflow (Disable + Move + conditional Delete)

## Testing

The provider includes comprehensive unit tests that use a fake AD adapter (no real AD required):

```powershell
Invoke-Pester -Path .\tests\Providers\ADIdentityProvider.Tests.ps1
```

The tests validate:

- Provider contract compliance
- Identity resolution (GUID/UPN/sAMAccountName)
- Idempotency of all operations
- `AllowDelete` gating behavior
- Capability advertisement

## Security Considerations

1. **Credential handling**: If using `-Credential`, ensure credentials are sourced from a secure store (not hardcoded).
2. **Delete opt-in**: The Delete capability is opt-in by design to prevent accidental deletions.
3. **Least privilege**: Grant only the minimum AD permissions required for your workflows.
4. **Audit**: Enable AD auditing to track lifecycle operations.

## Architecture

The provider uses an internal adapter layer (`New-IdleADAdapter`) that wraps AD cmdlets. This design:

- Keeps the provider testable without requiring a real AD environment
- Allows unit tests to inject a fake adapter
- Isolates AD cmdlet dependencies to a single module

## Troubleshooting

### Module not found

Ensure the ActiveDirectory module is installed and imported:

```powershell
Import-Module ActiveDirectory
Get-Module ActiveDirectory
```

### Permission denied

Verify the running account has appropriate AD permissions. Use `-Credential` to specify a service account if needed.

### Identity not found

Check the identity key format. Use GUID for unambiguous resolution:

```powershell
$user = Get-ADUser -Filter "sAMAccountName -eq 'username'" -Properties ObjectGuid
$provider.GetIdentity($user.ObjectGuid.ToString())
```

## Contributing

See the main repository [CONTRIBUTING.md](../../CONTRIBUTING.md) for guidelines.

## License

See the main repository [LICENSE.md](../../LICENSE.md).

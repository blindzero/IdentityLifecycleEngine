# Providers

Providers are the system-specific adapters (for example: Active Directory, Entra ID, Exchange Online).

The engine core talks only to provider contracts.

## Responsibilities

Providers typically:

- authenticate and manage sessions
- translate generic operations to system APIs
- are mockable for tests
- avoid global state

Steps should not handle authentication.

## Provider Aliases

When you supply providers to IdLE, you use a **hashtable** that maps **alias names** to **provider instances**:

```powershell
$providers = @{
    Identity = $adProvider
}
```

### Alias Naming

The alias name (hashtable key) is **completely flexible** and chosen by you (the host):

- It can be any valid PowerShell hashtable key
- Common patterns:
  - **Role-based**: `Identity`, `Entitlement`, `Messaging` (when you have one provider per role)
  - **Instance-based**: `SourceAD`, `TargetEntra`, `ProdForest`, `DevSystem` (when you have multiple providers)
- The built-in steps default to `'Identity'` if no `Provider` is specified in the step's `With` block

### How Workflows Reference Providers

Workflow steps can specify which provider to use via the `Provider` key in the `With` block:

```powershell
@{
    Name = 'Create user in source'
    Type = 'IdLE.Step.CreateIdentity'
    With = @{
        IdentityKey = 'newuser'
        Attributes  = @{ ... }
        Provider    = 'SourceAD'  # References the alias from the provider hashtable
    }
}
```

If `Provider` is not specified, it defaults to `'Identity'`:

```powershell
# These are equivalent when Provider is not specified:
With = @{ IdentityKey = 'user1'; Name = 'Department'; Value = 'IT' }
With = @{ IdentityKey = 'user1'; Name = 'Department'; Value = 'IT'; Provider = 'Identity' }
```

### Multiple Provider Example

```powershell
# Create provider instances
$sourceAD = New-IdleADIdentityProvider -Credential $sourceCred
$targetEntra = New-IdleEntraIdentityProvider -Credential $targetCred

# Map to custom aliases
$providers = @{
    SourceAD   = $sourceAD
    TargetEntra = $targetEntra
}

# Workflow steps reference the aliases
# Step 1: With = @{ Provider = 'SourceAD'; ... }
# Step 2: With = @{ Provider = 'TargetEntra'; ... }
```

## Acquire sessions via host

Providers can acquire sessions through a host-provided execution context callback:

- the host may allow interactive auth (or disallow it in CI)
- the host may cache sessions
- the provider declares requirements and asks for a session

This keeps IdLE.Core headless while supporting real-world auth flows.

## Testing providers

Providers should have contract tests that verify behavior against a mock or test harness.
Unit tests must not call live systems.

## Related

- [Testing](../advanced/testing.md)
- [Architecture](../advanced/architecture.md)

## Trust and security

Providers and the step registry are host-controlled extension points and should be treated as trusted code.
Workflows and lifecycle requests are data-only and must not contain executable objects.

For details, see `docs/advanced/security.md`.

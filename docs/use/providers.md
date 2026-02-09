---
title: Providers
sidebar_label: Providers
---

# Providers

Providers are the system-specific adapters (for example: Active Directory, Entra ID, Exchange Online) that connect
IdLE workflows to external systems.

For advanced provider documentation, including concepts, contracts, authentication, usage patterns, and examples, see: [Extend > Providers](../extend/providers.md)

---

## What are providers?

Providers:

- adapt IdLE workflows to external systems
- handle authentication via AuthSessionBroker
- translate generic operations to system APIs
- are mockable for tests
- provide capabilities, required by step types

See: [Provider responsibilities](../about/concepts.md#responsibilities)

## How to use providers?

Providers are supplied to plan execution as a hashtable with alias names.

:::info

As providers may require additional tools and configuration, they are not imported automatically and must be imported manually by the host.

:::

### Provider Resolution

When executing a plan, providers can be supplied in two ways:

1. **During planning** (recommended for most scenarios):

```powershell
Import-Module -Name IdLE.Provider.Mock

$providers = @{
    Identity = New-IdleMockIdentityProvider
}

# Build plan with providers
$plan = New-IdlePlan -WorkflowPath ./joiner.psd1 -Request $request -Providers $providers

# Execute without re-supplying providers (uses Plan.Providers)
$result = Invoke-IdlePlan -Plan $plan
```

2. **At execution time** (for provider override or exported plans):

```powershell
# Override providers at execution time
$otherProviders = @{
    Identity = New-IdleMockIdentityProvider -Config $differentConfig
}

$result = Invoke-IdlePlan -Plan $plan -Providers $otherProviders
```

#### Resolution Rules

- If `-Providers` is supplied to `Invoke-IdlePlan`, it **takes precedence** over `Plan.Providers`.
- If `-Providers` is **not** supplied, `Invoke-IdlePlan` uses `Plan.Providers` (if available).
- If neither is present, execution fails early with: `Providers are required. Provide -Providers to Invoke-IdlePlan or build the plan with Providers.`

#### Exported Plans

When a plan is exported without provider objects (for review or audit), providers must be supplied at execution time:

```powershell
# Export plan (without providers)
Export-IdlePlan -Plan $plan -Path ./plan.json

# Later: execute with providers (plan import functionality is planned for future release)
$result = Invoke-IdlePlan -Plan $plan -Providers $providers
```

### Provider Aliases

When you supply providers to IdLE, you use a **hashtable** that maps **alias names** to **provider instances**, e.g. `MockIdentity`

```powershell
$providers = @{
    MockIdentity = New-IdleMockIdentityProvider
}
```

#### Alias Naming

The alias name (hashtable key) is **completely flexible** and chosen by you (the host):

- It can be any valid PowerShell hashtable key
- Common patterns:
  - **Role-based**: `Identity`, `Entitlement`, `Messaging` (when you have one provider per role)
  - **Instance-based**: `SourceAD`, `TargetEntra`, `ProdForest`, `DevSystem` (when you have multiple providers)
- The built-in steps default to `'Identity'` if no `Provider` is specified in the step's `With` block

#### How Workflows Reference Providers

Workflow steps can specify which provider to use via the `Provider` key in the `With` block:

```powershell
@{
    Name = 'Create user'
    Type = 'IdLE.Step.CreateIdentity'
    With = @{
        IdentityKey = 'newuser'
        Attributes  = @{ ... }
        Provider    = 'MockIdentity'  # References the alias from the provider hashtable
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
$targetEntra = New-IdleEntraIDIdentityProvider -Credential $targetCred

# Map to custom aliases
$providers = @{
    SourceAD    = $sourceAD
    TargetEntra = $targetEntra
}

# Workflow steps reference the aliases
# Step 1: With = @{ Provider = 'SourceAD'; ... }
# Step 2: With = @{ Provider = 'TargetEntra'; ... }
```

## Authentication for Providers (AuthSessionBroker)

Many providers require authenticated connections (tokens, API clients, remote sessions).
IdLE keeps authentication out of the engine and out of individual providers by using a
host-supplied broker. Using the **AuthSessionBroker** is in particular helpful for scenarios that use different providers or different authentications for one provider in one workflow.

### AuthSessionType

AuthSessionBroker session values must specify an `AuthSessionType` that determines validation rules, lifecycle management, and telemetry behavior:

- **`OAuth`** - Token-based authentication (e.g., Microsoft Graph, Exchange Online)
- **`PSRemoting`** - PowerShell remoting execution context (e.g., Entra Connect)
- **`Credential`** - Credential-based authentication (e.g., Active Directory, mock providers)

Each provider documents its required `AuthSessionType` in its reference documentation.

### Example: Simple Single Credential

For the simplest case with just one credential:

```powershell
# Obtain credential (e.g., from a secure vault or credential manager)
$credential = Get-Credential -Message "Enter admin credentials"

# Create provider
$provider = New-IdleADIdentityProvider

# Create broker with single credential
$broker = New-IdleAuthSession -DefaultAuthSession $credential -AuthSessionType 'Credential'

# Use in plan
$plan = New-IdlePlan -WorkflowPath './workflow.psd1' -Request $request -Providers @{
    Identity = $provider
    AuthSessionBroker = $broker
}
```

### Example: Role-Based Credentials

For scenarios with multiple credentials for different roles, use `AuthSessionOptions` in workflows to select the appropriate credential:

```powershell
# Obtain credentials (e.g., from a secure vault or credential manager)
$tier0Credential = Get-Credential -Message "Enter Tier0 admin credentials"
$adminCredential = Get-Credential -Message "Enter regular admin credentials"

# Create provider
$provider = New-IdleADIdentityProvider

# Create broker with role-based credential mapping
$broker = New-IdleAuthSession -SessionMap @{
    @{ Role = 'Tier0' } = $tier0Credential
    @{ Role = 'Admin' } = $adminCredential
} -DefaultAuthSession $adminCredential -AuthSessionType 'Credential'

# Use in plan
$plan = New-IdlePlan -WorkflowPath './workflow.psd1' -Request $request -Providers @{
    Identity = $provider
    AuthSessionBroker = $broker
}
```

In the workflow definition, steps specify which role to use via `AuthSessionOptions`:

```powershell
With = @{
    ...
    AuthSessionOptions = @{ Role = 'Tier0' }
}
```

### Example: Entra ID with OAuth

```powershell
# Host obtains token (example using Azure PowerShell)
Connect-AzAccount
$token = (Get-AzAccessToken -ResourceUrl "https://graph.microsoft.com").Token

# Create provider
$provider = New-IdleEntraIDIdentityProvider

# Create broker with OAuth session type
$broker = New-IdleAuthSession -DefaultAuthSession $token -AuthSessionType 'OAuth'

# Use in plan
$plan = New-IdlePlan -WorkflowPath './workflow.psd1' -Request $request -Providers @{
    Identity = $provider
    AuthSessionBroker = $broker
}
```

### Example: Mixed Authentication Types (AD + EXO)

For workflows that need multiple providers with different authentication types:

```powershell
# Obtain credentials and tokens
$adCredential = Get-Credential -Message "Enter AD admin credentials"
Connect-AzAccount
$exoToken = (Get-AzAccessToken -ResourceUrl "https://outlook.office365.com").Token

# Create providers
$adProvider = New-IdleADIdentityProvider
$exoProvider = New-IdleExchangeOnlineProvider

# Create broker with mixed authentication types
$broker = New-IdleAuthSession -SessionMap @{
    # Active Directory uses Credential type
    @{ AuthSessionName = 'AD' } = @{ AuthSessionType = 'Credential'; Credential = $adCredential }
    
    # Exchange Online uses OAuth type
    @{ AuthSessionName = 'EXO' } = @{ AuthSessionType = 'OAuth'; Credential = $exoToken }
}

# Use in plan
$plan = New-IdlePlan -WorkflowPath './workflow.psd1' -Request $request -Providers @{
    AD = $adProvider
    EXO = $exoProvider
    AuthSessionBroker = $broker
}
```

In the workflow, steps specify which authentication session to use via `AuthSessionName`:

```powershell
# Step using AD (Credential)
@{
    Name = 'Create AD User'
    Type = 'IdLE.Step.CreateIdentity'
    With = @{
        AuthSessionName = 'AD'
        # ...
    }
}

# Step using EXO (OAuth)
@{
    Name = 'Create Mailbox'
    Type = 'IdLE.Step.CreateMailbox'
    With = @{
        AuthSessionName = 'EXO'
        # ...
    }
}
```

:::info

Please see the detailed [Provider Reference](../reference/providers.md) documentation for authentication help.

:::

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

```powershell
Import-Module -Name IdLE.Provider.Mock

$providers = @{
    Identity = New-IdleMockIdentityProvider
}

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

Each `AuthSessionBroker` must specify an `AuthSessionType` that determines validation rules, lifecycle management, and telemetry behavior:

- **`OAuth`** - Token-based authentication (e.g., Microsoft Graph, Exchange Online)
- **`PSRemoting`** - PowerShell remoting execution context (e.g., Entra Connect)
- **`Credential`** - Credential-based authentication (e.g., Active Directory, mock providers)

Each provider documents its required `AuthSessionType` in its reference documentation.

### Example: Active Directory with Credential Auth

```powershell
# Assuming you have credentials available (e.g., from a secure vault or credential manager)
$tier0Credential = Get-Credential -Message "Enter Tier0 admin credentials"
$adminCredential = Get-Credential -Message "Enter regular admin credentials"

# Create provider
$provider = New-IdleADIdentityProvider

# Create broker with role-based credential mapping and Credential session type
$broker = New-IdleAuthSession -SessionMap @{
    @{ Role = 'Tier0' } = $tier0Credential
    @{ Role = 'Admin' } = $adminCredential
} -DefaultAuthSession $adminCredential -AuthSessionType 'Credential'

# Use provider with broker
$plan = New-IdlePlan -WorkflowPath './workflow.psd1' -Request $request -Providers @{
    Identity = $provider
    AuthSessionBroker = $broker
}
```

### Example: Entra ID with OAuth

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

The different authentication sessions are used by the workflow definition by the steps via `AuthSessionOptions`.
```powershell
With = @{
    ...
    AuthSessionName = 'ActiveDirectory'
    AuthSessionOptions = @{ Role = 'Tier0' }
}
```

:::info

Please see the detailed [Provider Reference](../reference/providers.md) documentation for authentication help.

:::

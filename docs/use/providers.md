---
title: Providers
sidebar_label: Provider
---

# Providers

Providers are the system-specific adapters (for example: Active Directory, Entra ID, Exchange Online) that connect
IdLE workflows to external systems.

For complete provider documentation, including concepts, contracts, authentication, usage patterns, and examples, see:

**→ [Providers and Contracts](../reference/providers-and-contracts.md)** (single source of truth)

---

## Quick Reference

### What are providers?

Providers:

- Adapt IdLE workflows to external systems
- Handle authentication via AuthSessionBroker
- Translate generic operations to system APIs
- Are mockable for tests

See: [Provider responsibilities](../reference/providers-and-contracts.md#responsibilities)

### How to use providers

Providers are supplied to plan execution as a hashtable with alias names:

```powershell
$providers = @{
    Identity = New-IdleMockIdentityProvider
}

$result = Invoke-IdlePlan -Plan $plan -Providers $providers
```

See: [Provider aliases and usage](../reference/providers-and-contracts.md#usage)

### Available providers

- [Active Directory Provider](../reference/providers/provider-ad.md)
- [Entra ID Provider](../reference/providers/provider-entraID.md)

---

## Related

- [Providers and Contracts](../reference/providers-and-contracts.md) — Complete provider reference
- [Workflows](workflows.md) — How workflows reference providers
- [Steps](steps.md) — How steps use providers
- [Extensibility](../advanced/extensibility.md) — How to create custom providers

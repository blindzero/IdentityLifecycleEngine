---
title: Step Catalog
sidebar_label: Step Catalog
---

# Step Catalog

> Generated file. Do not edit by hand.
> Source: tools/Generate-IdleStepReference.ps1

This page documents built-in IdLE steps discovered from `Invoke-IdleStep*` functions in `IdLE.Steps.*` modules.

---

## CreateIdentity

- **Step Name**: `CreateIdentity`
- **Implementation**: `Invoke-IdleStepCreateIdentity`
- **Idempotent**: `Yes`
- **Contracts**: `Unknown`
- **Events**: Unknown

**Synopsis**

Creates a new identity in the target system.

**Description**

This is a provider-agnostic step. The host must supply a provider instance via
Context.Providers[&lt;ProviderAlias&gt;] that implements CreateIdentity(identityKey, attributes)
and returns an object with properties 'IdentityKey' and 'Changed'.

The step is idempotent by design: if the identity already exists, the provider
should return Changed = $false without creating a duplicate.

Authentication:
- If With.AuthSessionName is present, the step acquires an auth session via
  Context.AcquireAuthSession(Name, Options) and passes it to the provider method
  if the provider supports an AuthSession parameter.
- With.AuthSessionOptions (optional, hashtable) is passed to the broker for
  session selection (e.g., `@{ Role = 'Tier0' }`).
- ScriptBlocks in AuthSessionOptions are rejected (security boundary).

**Inputs (With.\*)**

| Key | Required |
| --- | --- |
| IdentityKey | Yes |
| Attributes | Yes |

---

## DeleteIdentity

- **Step Name**: `DeleteIdentity`
- **Implementation**: `Invoke-IdleStepDeleteIdentity`
- **Idempotent**: `Yes`
- **Contracts**: `Unknown`
- **Events**: Unknown

**Synopsis**

Deletes an identity from the target system.

**Description**

This is a provider-agnostic step. The host must supply a provider instance via
Context.Providers[&lt;ProviderAlias&gt;] that implements DeleteIdentity(identityKey)
and returns an object with properties 'IdentityKey' and 'Changed'.

The step is idempotent by design: if the identity is already deleted, the provider
should return Changed = $false.

IMPORTANT: This step requires the provider to advertise the IdLE.Identity.Delete
capability, which is typically opt-in for safety. The provider must be configured
to allow deletion (e.g., AllowDelete = $true for AD provider).

Authentication:
- If With.AuthSessionName is present, the step acquires an auth session via
  Context.AcquireAuthSession(Name, Options) and passes it to the provider method
  if the provider supports an AuthSession parameter.
- With.AuthSessionOptions (optional, hashtable) is passed to the broker for
  session selection (e.g., @{ Role = 'Tier0' }).
- ScriptBlocks in AuthSessionOptions are rejected (security boundary).

**Inputs (With.\*)**

_Unknown (not detected automatically). Document required With.* keys in the step help and/or use a supported pattern._

---

## DisableIdentity

- **Step Name**: `DisableIdentity`
- **Implementation**: `Invoke-IdleStepDisableIdentity`
- **Idempotent**: `Yes`
- **Contracts**: `Unknown`
- **Events**: Unknown

**Synopsis**

Disables an identity in the target system.

**Description**

This is a provider-agnostic step. The host must supply a provider instance via
Context.Providers[&lt;ProviderAlias&gt;] that implements DisableIdentity(identityKey)
and returns an object with properties 'IdentityKey' and 'Changed'.

The step is idempotent by design: if the identity is already disabled, the provider
should return Changed = $false.

Authentication:
- If With.AuthSessionName is present, the step acquires an auth session via
  Context.AcquireAuthSession(Name, Options) and passes it to the provider method
  if the provider supports an AuthSession parameter.
- With.AuthSessionOptions (optional, hashtable) is passed to the broker for
  session selection (e.g., @{ Role = 'Tier0' }).
- ScriptBlocks in AuthSessionOptions are rejected (security boundary).

**Inputs (With.\*)**

_Unknown (not detected automatically). Document required With.* keys in the step help and/or use a supported pattern._

---

## EmitEvent

- **Step Name**: `EmitEvent`
- **Implementation**: `Invoke-IdleStepEmitEvent`
- **Idempotent**: `Unknown`
- **Contracts**: `Unknown`
- **Events**: Unknown

**Synopsis**

Emits a custom event (demo step).

**Description**

This step does not change external state. It emits a custom event message.
The engine provides an EventSink on the execution context that the step can use
to write structured events.

**Inputs (With.\*)**

_Unknown (not detected automatically). Document required With.* keys in the step help and/or use a supported pattern._

---

## EnableIdentity

- **Step Name**: `EnableIdentity`
- **Implementation**: `Invoke-IdleStepEnableIdentity`
- **Idempotent**: `Yes`
- **Contracts**: `Unknown`
- **Events**: Unknown

**Synopsis**

Enables an identity in the target system.

**Description**

This is a provider-agnostic step. The host must supply a provider instance via
Context.Providers[&lt;ProviderAlias&gt;] that implements EnableIdentity(identityKey)
and returns an object with properties 'IdentityKey' and 'Changed'.

The step is idempotent by design: if the identity is already enabled, the provider
should return Changed = $false.

Authentication:
- If With.AuthSessionName is present, the step acquires an auth session via
  Context.AcquireAuthSession(Name, Options) and passes it to the provider method
  if the provider supports an AuthSession parameter.
- With.AuthSessionOptions (optional, hashtable) is passed to the broker for
  session selection (e.g., @{ Role = 'Tier0' }).
- ScriptBlocks in AuthSessionOptions are rejected (security boundary).

**Inputs (With.\*)**

_Unknown (not detected automatically). Document required With.* keys in the step help and/or use a supported pattern._

---

## EnsureAttribute

- **Step Name**: `EnsureAttribute`
- **Implementation**: `Invoke-IdleStepEnsureAttribute`
- **Idempotent**: `Yes`
- **Contracts**: `Provider must implement method: EnsureAttribute`
- **Events**: Unknown

**Synopsis**

Ensures that an identity attribute matches the desired value.

**Description**

This is a provider-agnostic step. The host must supply a provider instance via
Context.Providers[&lt;ProviderAlias&gt;]. The provider must implement an EnsureAttribute
method with the signature (IdentityKey, Name, Value) and return an object that
contains a boolean property 'Changed'.

The step is idempotent by design: it converges state to the desired value.

Authentication:
- If With.AuthSessionName is present, the step acquires an auth session via
  Context.AcquireAuthSession(Name, Options) and passes it to the provider method
  if the provider supports an AuthSession parameter.
- With.AuthSessionOptions (optional, hashtable) is passed to the broker for
  session selection (e.g., @{ Role = 'Tier0' }).
- ScriptBlocks in AuthSessionOptions are rejected (security boundary).

**Inputs (With.\*)**

| Key | Required |
| --- | --- |
| IdentityKey | Yes |
| Name | Yes |
| Value | Yes |

---

## EnsureEntitlement

- **Step Name**: `EnsureEntitlement`
- **Implementation**: `Invoke-IdleStepEnsureEntitlement`
- **Idempotent**: `Yes`
- **Contracts**: `Unknown`
- **Events**: Unknown

**Synopsis**

Ensures that an entitlement assignment is present or absent for an identity.

**Description**

This provider-agnostic step uses entitlement provider contracts to converge
an assignment to the desired state. The host must supply a provider instance
via `Context.Providers[&lt;ProviderAlias&gt;]` that implements:

- ListEntitlements(identityKey)
- GrantEntitlement(identityKey, entitlement)
- RevokeEntitlement(identityKey, entitlement)

The step is idempotent and only calls Grant/Revoke when the assignment needs
to change.

Authentication:
- If With.AuthSessionName is present, the step acquires an auth session via
  Context.AcquireAuthSession(Name, Options) and passes it to the provider methods
  if the provider supports an AuthSession parameter.
- With.AuthSessionOptions (optional, hashtable) is passed to the broker for
  session selection (e.g., @{ Role = 'Tier0' }).
- ScriptBlocks in AuthSessionOptions are rejected (security boundary).

**Inputs (With.\*)**

| Key | Required |
| --- | --- |
| IdentityKey | Yes |
| Entitlement | Yes |
| State | Yes |

---

## MoveIdentity

- **Step Name**: `MoveIdentity`
- **Implementation**: `Invoke-IdleStepMoveIdentity`
- **Idempotent**: `Yes`
- **Contracts**: `Unknown`
- **Events**: Unknown

**Synopsis**

Moves an identity to a different container/OU in the target system.

**Description**

This is a provider-agnostic step. The host must supply a provider instance via
Context.Providers[&lt;ProviderAlias&gt;] that implements MoveIdentity(identityKey, targetContainer)
and returns an object with properties 'IdentityKey' and 'Changed'.

The step is idempotent by design: if the identity is already in the target container,
the provider should return Changed = $false.

Authentication:
- If With.AuthSessionName is present, the step acquires an auth session via
  Context.AcquireAuthSession(Name, Options) and passes it to the provider method
  if the provider supports an AuthSession parameter.
- With.AuthSessionOptions (optional, hashtable) is passed to the broker for
  session selection (e.g., @{ Role = 'Tier0' }).
- ScriptBlocks in AuthSessionOptions are rejected (security boundary).

**Inputs (With.\*)**

| Key | Required |
| --- | --- |
| IdentityKey | Yes |
| TargetContainer | Yes |

---

## TriggerDirectorySync

- **Step Name**: `TriggerDirectorySync`
- **Implementation**: `Invoke-IdleStepTriggerDirectorySync`
- **Idempotent**: `Unknown`
- **Contracts**: `Unknown`
- **Events**: Unknown

**Synopsis**

Triggers a directory sync cycle and optionally waits for completion.

**Description**

This is a provider-agnostic step. The host must supply a provider instance via
Context.Providers[&lt;ProviderAlias&gt;] that implements:
- StartSyncCycle(PolicyType, AuthSession)
- GetSyncCycleState(AuthSession)

The step is designed for remote execution and requires an elevated auth session
provided by the host's AuthSessionBroker.

Authentication:
- With.AuthSessionName (required): routing key for AuthSessionBroker
- With.AuthSessionOptions (optional, hashtable): forwarded to broker for session selection
- ScriptBlocks in AuthSessionOptions are rejected (security boundary)

**Inputs (With.\*)**

_Unknown (not detected automatically). Document required With.* keys in the step help and/or use a supported pattern._

---

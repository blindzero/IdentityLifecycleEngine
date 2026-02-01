# EnsureEntitlement

> Generated file. Do not edit by hand.
> Source: tools/Generate-IdleStepReference.ps1

## Summary

- **Step Type**: `EnsureEntitlement`
- **Module**: `IdLE.Steps.Common`
- **Implementation**: `Invoke-IdleStepEnsureEntitlement`
- **Idempotent**: `Yes`
- **Contracts**: `Unknown`
- **Events**: Unknown

## Synopsis

Ensures that an entitlement assignment is present or absent for an identity.

## Description

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
  session selection (e.g., @\{ Role = 'Tier0' \}).

- ScriptBlocks in AuthSessionOptions are rejected (security boundary).

## Inputs (With.*)

| Key | Required |
| --- | --- |
| IdentityKey | Yes |
| Entitlement | Yes |
| State | Yes |

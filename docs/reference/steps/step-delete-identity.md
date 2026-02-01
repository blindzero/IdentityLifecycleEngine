# DeleteIdentity

> Generated file. Do not edit by hand.
> Source: tools/Generate-IdleStepReference.ps1

## Summary

- **Step Type**: `DeleteIdentity`
- **Module**: `IdLE.Steps.Common`
- **Implementation**: `Invoke-IdleStepDeleteIdentity`
- **Idempotent**: `Yes`
- **Contracts**: `Unknown`
- **Events**: Unknown

## Synopsis

Deletes an identity from the target system.

## Description

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
  session selection (e.g., @\{ Role = 'Tier0' \}).

- ScriptBlocks in AuthSessionOptions are rejected (security boundary).

## Inputs (With.*)

_Unknown (not detected automatically). Document required With.* keys in the step help and/or use a supported pattern._

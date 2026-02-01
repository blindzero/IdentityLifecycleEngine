# DisableIdentity

> Generated file. Do not edit by hand.
> Source: tools/Generate-IdleStepReference.ps1

## Summary

- **Step Type**: `DisableIdentity`
- **Implementation**: `Invoke-IdleStepDisableIdentity`
- **Idempotent**: `Yes`
- **Contracts**: `Unknown`
- **Events**: Unknown

## Synopsis

Disables an identity in the target system.

## Description

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
  session selection (e.g., @\{ Role = 'Tier0' \}).

- ScriptBlocks in AuthSessionOptions are rejected (security boundary).

## Inputs (With.*)

_Unknown (not detected automatically). Document required With.* keys in the step help and/or use a supported pattern._

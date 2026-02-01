# CreateIdentity

> Generated file. Do not edit by hand.
> Source: tools/Generate-IdleStepReference.ps1

## Summary

- **Step Type**: `CreateIdentity`
- **Implementation**: `Invoke-IdleStepCreateIdentity`
- **Idempotent**: `Yes`
- **Contracts**: `Unknown`
- **Events**: Unknown

## Synopsis

Creates a new identity in the target system.

## Description

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
  session selection (e.g., @\{ Role = 'Tier0' \}).

- ScriptBlocks in AuthSessionOptions are rejected (security boundary).

## Inputs (With.*)

| Key | Required |
| --- | --- |
| IdentityKey | Yes |
| Attributes | Yes |

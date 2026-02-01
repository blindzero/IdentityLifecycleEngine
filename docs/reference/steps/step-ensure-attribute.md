# EnsureAttribute

> Generated file. Do not edit by hand.
> Source: tools/Generate-IdleStepReference.ps1

## Summary

- **Step Type**: `EnsureAttribute`
- **Module**: `IdLE.Steps.Common`
- **Implementation**: `Invoke-IdleStepEnsureAttribute`
- **Idempotent**: `Yes`
- **Contracts**: `Provider must implement method: EnsureAttribute`
- **Events**: Unknown

## Synopsis

Ensures that an identity attribute matches the desired value.

## Description

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
  session selection (e.g., @\{ Role = 'Tier0' \}).

- ScriptBlocks in AuthSessionOptions are rejected (security boundary).

## Inputs (With.*)

| Key | Required |
| --- | --- |
| IdentityKey | Yes |
| Name | Yes |
| Value | Yes |

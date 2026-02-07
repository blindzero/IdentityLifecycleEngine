# EnableIdentity

> Generated file. Do not edit by hand.
> Source: tools/Generate-IdleStepReference.ps1

## Summary

- **Step Type**: `EnableIdentity`
- **Module**: `IdLE.Steps.Common`
- **Implementation**: `Invoke-IdleStepEnableIdentity`
- **Idempotent**: `Yes`
- **Required Capabilities**: `IdLE.Identity.Enable`

## Synopsis

Enables an identity in the target system.

## Description

The host must supply a provider instance via
Context.Providers[&lt;ProviderAlias&gt;] that implements EnableIdentity(identityKey)
and returns an object with properties 'IdentityKey' and 'Changed'.

The step is idempotent by design: if the identity is already enabled, the provider
should return Changed = $false.

Authentication:

- If With.AuthSessionName is present, the step acquires an auth session via
  Context.AcquireAuthSession(Name, Options) and passes it to the provider method
  if the provider supports an AuthSession parameter.

- With.AuthSessionOptions (optional, hashtable) is passed to the broker for
  session selection (e.g., @\{ Role = 'Tier0' \}).

- ScriptBlocks in AuthSessionOptions are rejected (security boundary).

## Inputs (With.*)

This step may not require specific input keys, or they could not be detected automatically.
Please refer to the step description and examples for usage details.

## Example

```powershell
@{
  Name = 'EnableIdentity Example'
  Type = 'IdLE.Step.EnableIdentity'
  With = @{
    # See step description for available options
  }
}
```

## See Also

- [Capabilities Reference](../capabilities.md) - Details on required capabilities
- [Providers](../providers.md) - Available provider implementations
